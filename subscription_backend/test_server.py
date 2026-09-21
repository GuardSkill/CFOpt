import copy
import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
import server


class BuilderTests(unittest.TestCase):
    def test_subscription_link_origin_validation(self):
        c = {'subscription_token': 'secret&x', 'public_base_url': 'https://sub.example/'}
        links = server.subscription_links(c)
        self.assertEqual(links['自动/默认订阅'], 'https://sub.example/sub?token=secret%26x&style=pools')
        self.assertTrue(links['移动订阅'].endswith('&isp=CMCC'))
        for value in ['javascript:alert(1)', 'https://user:pass@sub.example', 'https://sub.example/path', 'https://sub.example?x=1']:
            with self.assertRaises(ValueError):
                server.public_base_url(value)

    def test_all_default_ini_pools_with_real_chain_names(self):
        codes = ['DE', 'GB', 'HK', 'JP', 'KR', 'SG', 'TW', 'US']
        ordinary = [{'name': f'{server.FLAGS[c]} {c} [CD#01 20MB/s]', 'servername': 'a.example',
                     'ws-opts': {'path': '/ranking/out.html?ed=2560&x=1', 'headers': {'Host': 'a.example'}}} for c in codes]
        text = '\n'.join('8.8.8.8:443#' + c for c in ['IE', 'AT', 'HK', 'JP', 'KR', 'SG', 'TW', 'US'])
        with tempfile.TemporaryDirectory() as directory, patch.object(server, 'ROOT', Path(directory)), patch.object(server, 'fetch', return_value=text.encode()):
            nodes, stats = server.add_chains({'proxyip_enabled': True}, ordinary)
            self.assertEqual(stats['chain_nodes'], 9)
            for n in nodes:
                if '↪' in n['name'] or '→' in n['name']:
                    self.assertEqual(n['ws-opts']['path'], '/ranking/out.html/proxyip=8.8.8.8:443?ed=2560&x=1')
            ini = (Path(__file__).resolve().parent.parent / 'CFOpt_Subconverter_lite_cmliussss.ini').read_text(encoding='utf-8')
            routing = server.compile_ini(ini, lambda url: 'DOMAIN-SUFFIX,example.com')
            groups, empty = server.make_groups(routing['definitions'], nodes)
            self.assertEqual(empty, [])
            for g in groups:
                if 'Pool' in g['name'] or '↪' in g['name']:
                    self.assertTrue(any(n['name'] in g['proxies'] for n in nodes), g['name'])
            self.assertEqual(len(set(n['name'] for n in nodes)), len(nodes))
            self.assertEqual(next(g for g in groups if g['name'] == 'Polymarket DE + IE Pool')['proxies'], [n['name'] for n in nodes if 'DE →' in n['name'] and 'IE [' in n['name']])
            self.assertEqual(next(g for g in groups if g['name'] == 'OKX HK Pool')['proxies'], [n['name'] for n in ordinary if 'HK [' in n['name']])
            self.assertEqual(next(g for g in groups if g['name'] == 'OKX HK Proxy ↪')['proxies'], [n['name'] for n in nodes if 'HK ↪' in n['name']])

    def test_proxyip_pool_filter_and_last_good(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(server, 'ROOT', Path(directory)):
            with patch.object(server, 'fetch', return_value=b'127.0.0.1:443#JP\n8.8.8.8:443#JP\n8.8.8.8:443#JP\n1.1.1.1:443#JP\ninvalid#HK'):
                pool, stale = server.proxyip_pool({'proxyip_per_country': 1})
                self.assertEqual(pool, {'JP': ['8.8.8.8:443']})
                self.assertFalse(stale)
            with patch.object(server, 'fetch', side_effect=OSError()):
                pool, stale = server.proxyip_pool({})
                self.assertTrue(stale)
                self.assertEqual(pool, {'JP': ['8.8.8.8:443']})
    def setUp(self):
        self.c = {'node_uri': 'vless://test-id@a.example:443?security=tls&type=ws&path=%2Fws%3Fed%3D2560&ech=cloudflare-ech.com',
                  'usage_url': 'https://usage.example/', 'hosts': [{'name': 'a.example'}, {'name': 'b.example'}],
                  'sources': [{'name': 'Mobile', 'url': 'https://mobile.example/', 'isp': 'CMCC', 'default': True},
                              {'name': 'Telecom', 'url': 'https://telecom.example/', 'isp': 'CTC', 'default': True}]}

    def test_account_total_not_host_usage(self):
        with patch.object(server, 'fetch', return_value=b'{"total":90000,"max":100000}'):
            weights, dynamic = server.host_weights(self.c)
            self.assertFalse(dynamic)
            self.assertEqual([w for _, w in weights], [1, 1])

    def test_high_usage_excluded_and_stale_ignored(self):
        usage = {'hosts': {'a.example': {'used': 90, 'limit': 100, 'updated_at': time.time()},
                           'b.example': {'used': 10, 'limit': 100, 'updated_at': time.time()}}}
        with patch.object(server, 'fetch', return_value=json.dumps(usage).encode()):
            weights, dynamic = server.host_weights(self.c)
            self.assertTrue(dynamic)
            self.assertEqual(weights[0][1], 0)
            self.assertGreater(weights[1][1], 0)
        usage['hosts']['a.example']['updated_at'] = 1
        with patch.object(server, 'fetch', return_value=json.dumps(usage).encode()):
            weights, _ = server.host_weights(self.c)
            self.assertEqual(weights[0][1], 1)

    def test_routes_groups_and_tls(self):
        template = {'proxies': [{'name': 'JP old'}, {'name': 'HK old'}],
                    'proxy-groups': [{'name': 'Proxy', 'proxies': ['JP old', 'HK old', 'DIRECT']},
                                     {'name': 'JP Pool', 'proxies': ['JP old']}], 'rules': ['MATCH,Proxy']}
        mobile = 'IP地址,端口,城市,TLS\n1.1.1.1,443,JP [BJ#01],true\n1.0.0.1,443,HK [BJ#01],true\n'
        telecom = 'IP地址,端口,城市,TLS\n8.8.8.8,443,JP [CD#01],true\n'
        def fetch(url, ttl=300):
            return ({'https://usage.example/': '{}', 'https://mobile.example/': mobile,
                     'https://telecom.example/': telecom}[url]).encode()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'template.json').write_text(json.dumps(template))
            with patch.object(server, 'ROOT', root), patch.object(server, 'fetch', fetch):
                result, status = server.build(self.c, 'CMCC')
                self.assertEqual(status['sources'], ['Mobile'])
                self.assertEqual(len(result['proxies']), 2)
                self.assertEqual(len(result['proxy-groups'][1]['proxies']), 1)
                self.assertEqual(result['proxies'][0]['ws-opts']['path'], '/ws?ed=2560')
                self.assertEqual(result['rules'], template['rules'])
                self.assertEqual(sorted(status['host_counts'].values()), [1, 1])
                result, status = server.build(self.c, 'CTC')
                self.assertEqual(status['sources'], ['Telecom'])
                self.assertEqual(result['proxies'][0]['server'], '8.8.8.8')

    def test_panel_accounts_and_shared_weight(self):
        c = copy.deepcopy(self.c)
        c['hosts'] = [{'name': 'a.example', 'usage_account': 1},
                      {'name': 'b.example', 'usage_account': 1},
                      {'name': 'c.example', 'usage_account': 2}]
        accounts = [{'ID': 1, 'UpdateTime': time.time() * 1000, 'Usage': {'success': True, 'total': 20, 'max': 100}},
                    {'ID': 2, 'UpdateTime': time.time() * 1000, 'Usage': {'success': True, 'total': 20, 'max': 100}}]
        with patch.object(server, 'fetch', return_value=b'{}'), patch.object(server, 'panel_accounts', return_value=accounts):
            weights, dynamic = server.host_weights(c)
            self.assertTrue(dynamic)
            self.assertAlmostEqual(weights[0][1] + weights[1][1], weights[2][1])
            accounts[0]['Usage']['total'] = 120
            weights, dynamic = server.host_weights(c)
            self.assertEqual(weights[0][1], 0)
            self.assertEqual(weights[1][1], 0)
            accounts[1]['Usage']['total'] = 120
            with self.assertRaises(ValueError):
                server.host_weights(c)

    def test_no_mapping_does_not_claim_dynamic(self):
        accounts = [{'ID': 1, 'UpdateTime': time.time() * 1000, 'Usage': {'success': True, 'total': 80, 'max': 100}}]
        with patch.object(server, 'fetch', return_value=b'{}'), patch.object(server, 'panel_accounts', return_value=accounts):
            weights, dynamic = server.host_weights(self.c)
            self.assertFalse(dynamic)
            self.assertEqual([w for _, w in weights], [1, 1])

    def test_ini_remote_order_duplicate_groups_and_empty_chain(self):
        ini = '[custom]\nruleset=Direct,[]DOMAIN,local.test\nruleset=Proxy,https://rules.example/list\nruleset=Proxy,[]FINAL\ncustom_proxy_group=Proxy`select`[]JP Pool`.*\ncustom_proxy_group=Direct`select`[]DIRECT\ncustom_proxy_group=JP Pool`url-test`JP \\[`https://test.example`300,,50\ncustom_proxy_group=Chain`url-test`JP ↪ \\[`https://test.example`300\ncustom_proxy_group=Direct`select`[]DIRECT`[]Proxy\n'
        routing = server.compile_ini(ini, lambda url: '# comment\nIP-CIDR,1.1.1.0/24,no-resolve\n')
        self.assertEqual(routing['rules'], ['DOMAIN,local.test,Direct', 'IP-CIDR,1.1.1.0/24,Proxy,no-resolve', 'MATCH,Proxy'])
        groups, empty = server.make_groups(routing['definitions'], [{'name': 'JP [test]'}])
        self.assertEqual(len([g for g in groups if g['name'] == 'Direct']), 1)
        self.assertEqual(next(g for g in groups if g['name'] == 'JP Pool')['proxies'], ['JP [test]'])
        self.assertEqual(next(g for g in groups if g['name'] == 'Chain')['proxies'], ['REJECT'])
        self.assertEqual(empty, ['Chain'])

    def test_last_good_remote_rules_and_url_isolation(self):
        c = {'rule_template_url': 'https://rules.example/a'}
        ini = '[custom]\nruleset=Proxy,[]FINAL\ncustom_proxy_group=Proxy`select`.*'
        with tempfile.TemporaryDirectory() as directory, patch.object(server, 'ROOT', Path(directory)):
            with patch.object(server, 'fetch', return_value=ini.encode()):
                _, rules, status = server.remote_routing(c, [{'name': 'JP [test]'}])
                self.assertFalse(status['rules_stale'])
            with patch.object(server, 'fetch', side_effect=OSError()):
                _, fallback, status = server.remote_routing(c, [{'name': 'HK [test]'}])
                self.assertEqual(rules, fallback)
                self.assertTrue(status['rules_stale'])
                with self.assertRaises(OSError):
                    server.remote_routing({'rule_template_url': 'https://rules.example/b'}, [])

    def test_group_counts_nested_and_invalid_cycle_keeps_snapshot(self):
        nodes = [{'name': 'JP [test]'}]
        groups = [{'name': 'A', 'proxies': ['B', 'JP [test]']}, {'name': 'B', 'proxies': ['JP [test]']}]
        self.assertEqual(server.group_counts(groups, nodes), {'A': 1, 'B': 1})
        c = {'rule_template_url': 'https://rules.example/a'}
        good = '[custom]\nruleset=A,[]FINAL\ncustom_proxy_group=A`select`.*'
        bad = '[custom]\nruleset=A,[]FINAL\ncustom_proxy_group=A`select`[]B\ncustom_proxy_group=B`select`[]A'
        with tempfile.TemporaryDirectory() as directory, patch.object(server, 'ROOT', Path(directory)):
            with patch.object(server, 'fetch', return_value=good.encode()):
                server.remote_routing(c, nodes)
            with patch.object(server, 'fetch', return_value=bad.encode()):
                _, _, status = server.remote_routing(c, nodes)
                self.assertTrue(status['rules_stale'])
            with patch.object(server, 'fetch', side_effect=OSError()):
                groups, _, _ = server.remote_routing(c, nodes)
                self.assertEqual(groups[0]['proxies'], ['JP [test]'])

    def test_visual_form_preserves_private_credentials(self):
        c = copy.deepcopy(self.c)
        c['usage_panel'] = {'url': 'https://panel.example', 'admin_cookie': 'secret'}
        fields = {k: [v] for k, v in {'node_uri': c['node_uri'], 'usage_url': c['usage_url'], 'rule_template_url': 'https://rules.example/a', 'rule_cache_seconds': '300', 'disable_gap': '0.35', 'usage_panel_url': 'https://panel.example', 'host_count': '1', 'source_count': '1', 'host_name_0': 'a.example', 'host_account_0': '3', 'host_enabled_0': 'on', 'source_name_0': 'Mobile', 'source_url_0': 'https://mobile.example', 'source_default_0': 'on'}.items()}
        result = server.form_config(c, fields)
        self.assertEqual(result['usage_panel']['admin_cookie'], 'secret')
        self.assertEqual(result['hosts'][0]['usage_account'], 3)
        self.assertTrue(result['sources'][0]['default'])
        self.assertIn('Host 多选', server.admin_page(result))
        self.assertIn('width=device-width', server.admin_page(result))

    def test_classic_groups_and_subscription_filename(self):
        rules = ['DOMAIN-SUFFIX,openai.com,OpenAI', 'MATCH,Others']
        with tempfile.TemporaryDirectory() as directory, patch.object(server, 'ROOT', Path(directory)):
            (Path(directory) / 'classic-routing.json').write_text(json.dumps({'rules': rules}), encoding='utf-8')
            nodes = [{'name': '🇹🇼 TW [test]'}, {'name': '🇯🇵 JP [test]'}]
            groups, actual, status = server.classic_routing(nodes)
            self.assertEqual([g['name'] for g in groups], [g[0] for g in server.CLASSIC_GROUPS])
            self.assertEqual(actual, rules)
            self.assertEqual(next(g for g in groups if g['name'] == 'TWMedia')['proxies'], ['🇹🇼 TW [test]', 'Proxy'])
            self.assertEqual(status['pool_counts']['OpenAI'], 2)
        c = {'subscription_filenames': {'ctc': '成都电信_yuanclash.yaml'}}
        self.assertEqual(server.subscription_filename(c, 'CTC'), '成都电信_yuanclash.yaml')
        with self.assertRaises(ValueError):
            server.subscription_filename({'subscription_filenames': {'ctc': '../bad.yaml'}}, 'CTC')

    def test_subscription_links_pin_selected_style(self):
        c = {'public_base_url': 'https://sub.example', 'subscription_token': 'secret', 'output_style': 'pools'}
        self.assertIn('style=pools', server.subscription_links(c)['电信订阅'])

    def test_subscription_userinfo_maps_requests_to_kib(self):
        c = {'hosts': [{'usage_account': 1}, {'usage_account': 2}],
             'request_quota_display': {'total_requests': 700000, 'requests_per_kib': 1000, 'expire': 4102329600}}
        accounts = [
            {'ID': 1, 'Usage': {'success': True, 'total': 2500, 'max': 100000}},
            {'ID': 2, 'Usage': {'success': True, 'total': 5000, 'max': 100000}},
            {'ID': 99, 'Usage': {'success': True, 'total': 90000, 'max': 100000}},
        ]
        with patch.object(server, 'panel_accounts', return_value=accounts):
            self.assertEqual(server.subscription_userinfo(c),
                             'upload=7680; download=0; total=204800; expire=4102329600')
        with patch.object(server, 'panel_accounts', side_effect=OSError()):
            self.assertEqual(server.subscription_userinfo(c),
                             'upload=0; download=0; total=716800; expire=4102329600')


if __name__ == '__main__':
    unittest.main()
