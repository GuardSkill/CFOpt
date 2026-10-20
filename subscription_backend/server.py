"""Private, dependency-free Mihomo subscription builder."""
import base64
import copy
import csv
import concurrent.futures
import html
import hashlib
import hmac
import io
import ipaddress
import json
import os
import re
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(os.environ.get('CFOPT_DATA_DIR', str(Path(__file__).resolve().parent)))
LOCK = threading.RLock()
CACHE = {}
USAGE_LOCK = threading.RLock()
USAGE_CACHE = {}
USAGE_RETRY_AFTER = {}
USAGE_CACHE_SECONDS = 3600
USAGE_RETRY_SECONDS = 300
DEFAULT_RULE_URL = 'https://raw.githubusercontent.com/GuardSkill/CFOpt/main/CFOpt_Subconverter_lite_cmliussss.ini'
DEFAULT_PUBLIC_URL = 'http://net.deepdns.dpdns.org'
DEFAULT_PROXYIP_URL = 'https://raw.githubusercontent.com/GuardSkill/CFOpt/main/proxyip-best.txt'
CHAIN_ROUTES = {'DE': ['IE', 'AT'], 'GB': ['IE'], **{c: [c] for c in ('HK', 'JP', 'KR', 'SG', 'TW', 'US')}}
FLAGS = {c: ''.join(chr(127397 + ord(x)) for x in c) for c in ('DE', 'GB', 'IE', 'AT', 'HK', 'JP', 'KR', 'SG', 'TW', 'US')}
CUSTOM_REGIONS = ('JP', 'KR', 'HK', 'SG', 'TW')
CLASSIC_GROUPS = [
    ('Proxy', 'all', 'https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/icon/qure/color/Proxy.png'),
    ('OpenAI', 'proxy-direct-all', 'https://raw.githubusercontent.com/HotKids/Rules/master/Quantumult/X/Images/Color/ChatGPT.png'),
    ('Netflix', 'proxy-direct-all', 'https://raw.githubusercontent.com/HotKids/Rules/master/Quantumult/X/Images/Icons/Netflix.png'),
    ('DisneyPlus', 'proxy-direct-all', 'https://raw.githubusercontent.com/HotKids/Rules/master/Quantumult/X/Images/Icons/Disney+.png'),
    ('TWMedia', 'tw', 'https://raw.githubusercontent.com/HatScripts/circle-flags/refs/heads/gh-pages/flags/tw.svg'),
    ('Bilibili', 'direct', 'https://raw.githubusercontent.com/HotKids/Rules/master/Quantumult/X/Images/Icons/Bilibili.png'),
    ('Linkedin', 'direct', 'https://icons.getbootstrap.com/assets/icons/linkedin.svg'),
    ('Youtube', 'proxy-all', 'https://raw.githubusercontent.com/HotKids/Rules/master/Quantumult/X/Images/Icons/YouTube.png'),
    ('GlobalTV', 'proxy-all', 'https://raw.githubusercontent.com/HotKids/Rules/master/Quantumult/X/Images/Streaming.png'),
    ('Telegram', 'proxy-direct-all', 'https://raw.githubusercontent.com/HotKids/Rules/master/Quantumult/X/Images/Icons/Telegram.png'),
    ('Steam', 'direct', 'https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/icon/color/steam.png'),
    ('Epic', 'direct', 'https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/Quantumult/X/Images/Task/epic.png'),
    ('Apple', 'direct', 'https://raw.githubusercontent.com/HotKids/Rules/master/Quantumult/X/Images/Icons/Apple.png'),
    ('Others', 'proxy', 'https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/icon/qure/color/Final.png'),
]
ADMIN_CSS = '''
*:before,*:after{box-sizing:border-box}
select{width:100%;padding:11px 13px;margin-top:6px;border:1px solid #dce2ec;border-radius:8px;background:#fbfcff;color:#24314a;font-size:14px;font-family:inherit}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{font:15px/1.6 system-ui,-apple-system,"Segoe UI",sans-serif;margin:0;background:#f3f5fa;color:#24314a;padding:38px 40px 80px 270px;max-width:1600px}body:before{content:"CFOpt / Network";position:fixed;left:0;top:0;width:225px;height:100vh;background:#142139;color:#f8fafc;font-size:22px;font-weight:700;padding:34px 22px;box-shadow:6px 0 28px #17243b12}nav{position:fixed;left:16px;top:110px;width:190px;z-index:1}nav a{display:block;text-decoration:none;padding:12px 16px;color:#bfcbe2;margin:7px 0;border-radius:8px}nav a:hover,nav a.active{color:white;background:#293a57}h1{font-size:32px;letter-spacing:-1px;margin:0 0 8px}h1+p{color:#68768d;margin-bottom:24px}.eyebrow{color:#6576d8;letter-spacing:2px;font-size:12px;font-weight:700}.metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin:24px 0}.metric{background:white;border:1px solid #e0e5ef;border-radius:14px;padding:18px 22px}.metric span{display:block;font-size:28px;font-weight:700;color:#283855}.metric small{font-size:12px;color:#77859b}fieldset,details{min-width:0;background:white;border:1px solid #e0e5ef;border-radius:14px;padding:22px 26px;margin:24px 0;box-shadow:0 4px 18px #1b315306;scroll-margin:20px}legend{font-weight:700;font-size:17px;color:#233854;padding:0 8px}label{display:block;margin:14px 0;color:#51627c;font-size:13px;font-weight:600}input:not([type=checkbox]),textarea{width:100%;padding:11px 13px;margin-top:6px;border:1px solid #dce2ec;border-radius:8px;background:#fbfcff;color:#24314a;font-size:14px;font-family:inherit;transition:border-color .15s}input:focus,textarea:focus{outline:3px solid #6379ea18;border-color:#6379ea}input[readonly]{font-family:ui-monospace,monospace;color:#486396;background:#f3f6fd}input[type=checkbox]{accent-color:#6277df;width:18px;height:18px;vertical-align:middle}table{width:100%;border-collapse:collapse}th{text-align:left;font-size:12px;color:#8b96a9;font-weight:500}td{padding:5px 8px;border-bottom:1px solid #eef1f6}td:first-child{width:58px}td:last-child{width:150px}button{cursor:pointer;background:#6075dd;color:white;border:0;border-radius:8px;padding:11px 22px;font-weight:600;font-size:14px;box-shadow:0 3px 8px #6075dd20}button:hover{background:#4d62cb}button[data-copy]{background:#eef2ff;color:#5268c3;box-shadow:none;padding:8px 15px}small{color:#7c899d;font-size:12px}summary{cursor:pointer;color:#65738d}.status-box{background:#eef3fc;border-radius:10px;padding:18px}.pool-list{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.pool-row{display:flex;justify-content:space-between;gap:10px;background:white;padding:8px 12px;border-radius:7px;font-size:12px}.pool-row b{color:#5d72d2}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:0 18px}.wide{grid-column:1/-1}#status-message{color:#65758d}form>button{min-width:210px}fieldset fieldset{box-shadow:none;background:#fafbfe}a{color:#5e74d5}@media(max-width:1050px){body{padding:30px 22px 60px 225px}body:before{width:200px}nav{width:166px}.metrics{grid-template-columns:repeat(2,1fr)}.pool-list{grid-template-columns:repeat(2,1fr)}}@media(max-width:700px){body{padding:22px 14px}body:before,nav{display:none}h1{font-size:26px}fieldset{padding:16px}.metrics,.grid{grid-template-columns:1fr}.metrics{gap:10px}.metric{padding:14px}td{padding:4px}td:last-child{width:85px}.pool-list{grid-template-columns:1fr}}
'''
ADMIN_JS = """document.querySelectorAll('[data-copy]').forEach(b=>b.addEventListener('click',async()=>{const e=document.getElementById(b.dataset.copy);e.focus();e.select();let ok=false;try{if(navigator.clipboard&&window.isSecureContext){await navigator.clipboard.writeText(e.value);ok=true;}else{ok=document.execCommand('copy');}}catch(_){}const result=document.getElementById('copy-result');if(result)result.textContent=ok?'已复制订阅地址':'地址已选中，请按 Ctrl+C 复制';}));
async function loadStatus(){const msg=document.getElementById('status-message');if(!msg)return;msg.textContent='正在验证节点、规则和优选入口…';try{const r=await fetch(msg.dataset.endpoint||'/admin/status',{cache:'no-store'});if(!r.ok)throw Error();const s=await r.json();const set=(id,value)=>{const e=document.getElementById(id);if(e)e.textContent=value};set('metric-nodes',s.nodes);set('metric-chains',s.chain_nodes||0);set('metric-rules',s.rules);set('metric-groups',Object.keys(s.pool_counts||{}).length);const box=document.getElementById('pool-counts');if(box){box.replaceChildren();for(const [name,count] of Object.entries(s.pool_counts||{})){const row=document.createElement('div');row.className='pool-row';const label=document.createElement('span');label.textContent=name;const n=document.createElement('b');n.textContent=count+' 节点';row.append(label,n);box.append(row);}}if(s.selected_entries){msg.textContent='已生成 '+s.nodes+' 个节点 · '+s.selected_entries.map(x=>x.region+' '+x.count+' 个').join(' · ')+' · '+(s.rules_stale?'规则使用上次成功快照':'GitHub 规则已生效');}else{msg.textContent=(s.dynamic_usage?'账户用量加权已生效':'用量不可用或过期，等权回退')+' · '+(s.rules_stale?'规则使用上次成功快照':'GitHub 规则已生效')+' · '+(s.proxyip_stale?'ProxyIP 使用旧快照':'ProxyIP 已加载')+(s.empty_groups.length?' · 空池：'+s.empty_groups.join('、'):' · 所有策略池有节点');}}catch(_){msg.textContent='生成验证失败，请检查基础节点、CSV 与规则来源；旧配置没有被替换。';}}
document.getElementById('refresh-status')?.addEventListener('click',loadStatus);loadStatus();"""


def proxyip_pool(c):
    url = c.get('proxyip_url', DEFAULT_PROXYIP_URL)
    limit = int(c.get('proxyip_per_country', 10))
    if not 1 <= limit <= 50:
        raise ValueError('ProxyIP count must be 1–50')
    snapshot = ROOT / ('proxyip-' + hashlib.sha256(url.encode()).hexdigest() + '.json')
    stale = False
    try:
        pool = {}
        for line in fetch(url, 300).decode('utf-8-sig').splitlines():
            if '#' not in line or line.startswith('#'):
                continue
            address, code = (s.strip() for s in line.rsplit('#', 1))
            code = code.upper()
            if code not in ('AT', 'AU', 'DE', 'GB', 'HK', 'IE', 'JP', 'KR', 'SG', 'TW', 'US'):
                continue
            try:
                parsed = urllib.parse.urlsplit('tcp://' + address)
                ip = ipaddress.ip_address(parsed.hostname)
                if not ip.is_global or not parsed.port or parsed.username or parsed.path:
                    continue
                canonical = ('[' + str(ip) + ']' if ip.version == 6 else str(ip)) + ':' + str(parsed.port)
            except ValueError:
                continue
            values = pool.setdefault(code, [])
            if canonical not in values and len(values) < limit:
                values.append(canonical)
        if not pool:
            raise ValueError('Empty ProxyIP pool')
        with LOCK:
            temp = snapshot.with_suffix('.tmp')
            temp.write_text(json.dumps(pool), encoding='utf-8')
            os.chmod(temp, 0o600)
            os.replace(temp, snapshot)
    except Exception:
        if not snapshot.exists():
            raise
        pool = {code: values[:limit] for code, values in json.loads(snapshot.read_text()).items()}
        stale = True
    return pool, stale


def add_chains(c, ordinary):
    if not c.get('proxyip_enabled', False):
        return ordinary, {'chain_nodes': 0, 'proxyip_stale': False, 'proxyip_countries': {}}
    pool, stale = proxyip_pool(c)
    nodes, counts = [], {}
    for original in ordinary:
        nodes.append(original)
        entry = country(original['name'])
        for exit_country in CHAIN_ROUTES.get(entry, []):
            addresses = pool.get(exit_country, [])
            if not addresses:
                continue
            chain = copy.deepcopy(original)
            suffix = original['name'][original['name'].find('['):]
            chain['name'] = (f'{FLAGS[entry]} {entry} ↪ ' if entry == exit_country else f'{FLAGS[entry]} {entry} → {FLAGS[exit_country]} {exit_country} ') + suffix
            path = urllib.parse.urlsplit(original['ws-opts']['path'])
            # Insert BEFORE query, preserving ed=2560 and any other parameters.
            base = re.sub(r'/proxyip=[^/]*', '', path.path).rstrip('/')
            chain['ws-opts']['path'] = base + '/proxyip=' + ','.join(addresses) + ('?' + path.query if path.query else '')
            nodes.append(chain)
            key = entry + '→' + exit_country
            counts[key] = counts.get(key, 0) + 1
    return nodes, {'chain_nodes': len(nodes) - len(ordinary), 'ordinary_nodes': len(ordinary), 'chain_routes': counts, 'proxyip_stale': stale, 'proxyip_countries': {k: len(v) for k, v in pool.items()}}


def public_base_url(value):
    value = value.strip().rstrip('/')
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('', '/'):
        raise ValueError('Use an HTTP(S) origin without path, credentials or query')
    parsed.port  # Validate port syntax/range.
    return urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, '', '', ''))


def subscription_links(c):
    base = public_base_url(c.get('public_base_url', DEFAULT_PUBLIC_URL))
    token = urllib.parse.quote(c['subscription_token'], safe='')
    style = c.get('output_style', 'pools')
    return {name: f'{base}/admin/sub/{token}/{isp or "AUTO"}/{style}'
            for name, isp in [('自动/默认订阅', ''), ('移动订阅', 'CMCC'), ('电信订阅', 'CTC')]}


def custom_subscription_link(c):
    base = public_base_url(c.get('public_base_url', DEFAULT_PUBLIC_URL))
    token = urllib.parse.quote(c['subscription_token'], safe='')
    return f'{base}/admin/custom/sub/{token}'


def allowed_admin_origin(c, origin, host):
    """Allow same-host writes and the explicitly configured public origin."""
    if not origin:
        return True
    try:
        parsed = urllib.parse.urlsplit(origin)
        if parsed.scheme not in ('http', 'https') or not parsed.netloc:
            return False
        request_host = str(host or '').lower()
        origins = {request_host}
        public = urllib.parse.urlsplit(public_base_url(c.get('public_base_url', DEFAULT_PUBLIC_URL)))
        origins.add(public.netloc.lower())
        for value in c.get('admin_allowed_origins', []):
            try:
                allowed = urllib.parse.urlsplit(public_base_url(value))
                origins.add(allowed.netloc.lower())
            except (ValueError, TypeError):
                continue
        if parsed.netloc.lower() in origins:
            return True
        # Some browsers/proxies omit the port in Origin. Treat the same
        # hostname as the direct admin origin; the admin endpoint still
        # requires Basic authentication.
        request_hostname = urllib.parse.urlsplit('//'+request_host).hostname
        return bool(request_hostname and parsed.hostname and parsed.hostname.lower() == request_hostname.lower())
    except (ValueError, TypeError):
        return False


def subscription_filename(c, isp=''):
    key = {'CMCC': 'cmcc', 'CTC': 'ctc'}.get(isp, 'default')
    value = c.get('subscription_filenames', {}).get(key, 'yuanclash.yaml').strip()
    if not value.lower().endswith(('.yaml', '.yml')) or not 1 <= len(value) <= 120 or re.search(r'[\\/:*?"<>|\x00-\x1f]', value):
        raise ValueError('Invalid subscription filename')
    return value


def compile_ini(text, read):
    section, entries = '', []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith((';', '#')):
            continue
        if line.startswith('['):
            section = line.lower()
        elif section == '[custom]' and '=' in line:
            key, value = line.split('=', 1)
            entries.append((key.strip(), value.strip()))
    definitions, specs, duplicates = {}, [], []
    for key, value in entries:
        if key == 'custom_proxy_group':
            parts = value.split('`')
            if len(parts) < 3 or parts[1] not in ('select', 'url-test', 'fallback', 'load-balance'):
                raise ValueError('Unsupported group definition')
            if parts[0] in definitions:
                duplicates.append(parts[0])
            else:
                # Match the existing subconverter output: the first definition
                # wins when an INI repeats the same policy-group name.
                definitions[parts[0]] = parts
        elif key == 'ruleset':
            policy, source = value.split(',', 1)
            specs.append((policy, source))
    if not definitions or not specs:
        raise ValueError('INI must define groups and rulesets')
    urls = list(dict.fromkeys(s for _, s in specs if not s.startswith('[]')))
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        contents = dict(zip(urls, pool.map(read, urls)))
    rules = []
    valid = set(definitions) | {'DIRECT', 'REJECT'}
    allowed = {'DOMAIN', 'DOMAIN-SUFFIX', 'DOMAIN-KEYWORD', 'DOMAIN-REGEX', 'IP-CIDR', 'IP-CIDR6', 'GEOIP', 'GEOSITE', 'SRC-IP-CIDR', 'DST-PORT', 'SRC-PORT', 'PROCESS-NAME', 'PROCESS-PATH', 'NETWORK', 'MATCH', 'FINAL'}
    for policy, source in specs:
        if policy not in valid:
            raise ValueError('Unknown rule policy')
        lines = [source[2:]] if source.startswith('[]') else contents[source].splitlines()
        for line in lines:
            line = line.strip()
            if not line or line.startswith(('#', ';', '//')):
                continue
            parts = [p.strip() for p in line.split(',')]
            kind = parts[0].upper()
            if kind not in allowed:
                raise ValueError('Unsupported ruleset syntax')
            if kind in ('FINAL', 'MATCH'):
                rules.append('MATCH,' + policy)
            elif len(parts) >= 2:
                options = parts[2:]
                if any(p != 'no-resolve' for p in options):
                    raise ValueError('Unsupported ruleset options')
                rules.append(','.join([kind, parts[1], policy] + options))
            else:
                raise ValueError('Invalid rule')
    if not rules or not rules[-1].startswith('MATCH,'):
        raise ValueError('Missing final rule')
    return {'definitions': list(definitions.values()), 'rules': rules, 'duplicate_groups': duplicates,
            'ruleset_count': len(specs), 'policies': list(dict.fromkeys(policy for policy, _ in specs))}


def remote_routing(c, nodes):
    url = c['rule_template_url']
    ttl = max(60, min(86400, int(c.get('rule_cache_seconds', 300))))
    snapshot = ROOT / ('routing-' + hashlib.sha256(url.encode()).hexdigest() + '.json')
    stale = False
    try:
        routing = compile_ini(fetch(url, ttl).decode('utf-8-sig'), lambda u: fetch(u, ttl).decode('utf-8-sig'))
        # Validate regex before storing a complete last-known-good snapshot.
        checked_groups, _ = make_groups(routing['definitions'], nodes)
        group_counts(checked_groups, nodes)
        with LOCK:
            temp = snapshot.with_suffix('.tmp')
            temp.write_text(json.dumps(routing, ensure_ascii=False), encoding='utf-8')
            os.chmod(temp, 0o600)
            os.replace(temp, snapshot)
    except Exception:
        if not snapshot.exists():
            raise
        routing = json.loads(snapshot.read_text(encoding='utf-8'))
        stale = True
    groups, empty = make_groups(routing['definitions'], nodes)
    counts = group_counts(groups, nodes)
    return groups, routing['rules'], {'rule_template_url': url, 'rules_stale': stale, 'empty_groups': empty, 'duplicate_groups': routing.get('duplicate_groups', []), 'ruleset_count': routing.get('ruleset_count', 0), 'pool_counts': counts}


def group_counts(groups, nodes):
    by_name = {g['name']: g for g in groups}
    node_names = {n['name'] for n in nodes}
    def reachable(name, visited):
        if name in node_names:
            return {name}
        if name not in by_name:
            return set()
        if name in visited:
            raise ValueError('Group reference cycle')
        result = set()
        for ref in by_name[name]['proxies']:
            result |= reachable(ref, visited | {name})
        return result
    return {g['name']: len(reachable(g['name'], set())) for g in groups}


def make_groups(definitions, nodes):
    groups, empty = [], []
    valid = {p[0] for p in definitions} | {'DIRECT', 'REJECT'}
    for parts in definitions:
        name, kind, *fields = parts
        group = {'name': name, 'type': kind}
        selectors = fields
        if kind != 'select':
            if len(fields) < 3:
                raise ValueError('Missing test URL/interval')
            selectors, test_url, timer = fields[:-2], fields[-2], fields[-1]
            group['url'] = test_url
            timings = timer.split(',')
            group['interval'] = int(timings[0])
            if len(timings) > 2 and timings[2]:
                group['tolerance'] = int(timings[2])
        members = []
        for selector in selectors:
            if selector.startswith('[]'):
                ref = selector[2:]
                if ref not in valid:
                    raise ValueError('Unknown group reference')
                members.append(ref)
            else:
                pattern = re.compile(selector)
                members.extend(n['name'] for n in nodes if pattern.search(n['name']))
        if not members:
            empty.append(name)
        group['proxies'] = list(dict.fromkeys(members or ['REJECT']))
        groups.append(group)
    return groups, empty


def classic_routing(nodes):
    data = json.loads((ROOT / 'classic-routing.json').read_text(encoding='utf-8'))
    rules = data.get('rules')
    if not isinstance(rules, list) or not rules or not rules[-1].startswith('MATCH,'):
        raise ValueError('Invalid classic routing snapshot')
    names = [n['name'] for n in nodes]
    tw = [n['name'] for n in nodes if country(n['name']) == 'TW']
    groups = []
    for name, mode, icon in CLASSIC_GROUPS:
        choices = {'all': names, 'proxy-direct-all': ['Proxy', 'DIRECT', *names],
                   'tw': [*tw, 'Proxy'], 'direct': ['DIRECT', 'Proxy'],
                   'proxy-all': ['Proxy', *names], 'proxy': ['Proxy', 'DIRECT']}[mode]
        groups.append({'name': name, 'type': 'select', 'proxies': list(dict.fromkeys(choices)), 'icon': icon})
    valid = {g['name'] for g in groups} | {'DIRECT', 'REJECT'}
    split_rules = [rule.split(',') for rule in rules]
    if any(len(parts) < (2 if parts[0] == 'MATCH' else 3) for parts in split_rules):
        raise ValueError('Invalid classic rule')
    policies = [parts[1] if parts[0] == 'MATCH' else parts[2] for parts in split_rules]
    if any(policy not in valid for policy in policies):
        raise ValueError('Unknown classic routing policy')
    return groups, rules, {'rule_template_url': 'local classic snapshot', 'rules_stale': False,
                           'empty_groups': [], 'duplicate_groups': [], 'ruleset_count': 0,
                           'pool_counts': group_counts(groups, nodes), 'output_style': 'classic'}


def admin_page(c):
    def field(name, label, value='', kind='text'):
        return f'<label>{html.escape(label)}<input type="{kind}" name="{name}" value="{html.escape(str(value), quote=True)}"></label>'
    page = '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CFOpt 订阅管理</title><style>body{font:16px system-ui;max-width:1100px;margin:32px auto;padding:16px;background:#f4f6fa;color:#17243b}fieldset{background:white;border:1px solid #dae0e9;border-radius:12px;margin:20px 0;padding:20px}label{display:block;margin:12px 0}input:not([type=checkbox]){box-sizing:border-box;width:100%;padding:10px;border:1px solid #ccd3dd;border-radius:6px}table{width:100%}td{padding:4px}button{padding:12px 24px;background:#235ac6;color:white;border:0;border-radius:8px}small{color:#526079}</style><h1>CFOpt 订阅管理</h1><p>表单保存后在客户端更新订阅生效。空白行可添加 host 或 CSV。后台信息请勿截图公开。</p><form method="post" action="/admin"><input type="hidden" name="mode" value="form"><fieldset><legend>节点与远程路由规则</legend>'
    links = subscription_links(c) if c.get('subscription_token') else {}
    card = '<fieldset><legend>订阅地址（可直接导入 Clash Party）</legend>'
    for i, (label, link) in enumerate(links.items()):
        card += f'<label>{html.escape(label)}<input id="subscription-{i}" readonly value="{html.escape(link, quote=True)}"></label><button type="button" data-copy="subscription-{i}">复制地址</button> '
    card += '<p id="copy-result" role="status"></p><small>订阅 token 是访问凭据，请勿公开完整链接。</small>'
    if c.get('public_base_url', DEFAULT_PUBLIC_URL).startswith('http:'):
        card += '<p style="color:#a33">当前公网地址使用 HTTP，密码和订阅 token 无传输加密保护，建议启用 HTTPS。</p>'
    card += '</fieldset><script src="/admin.js" defer></script>'
    page = page.replace('<form method="post" action="/admin">', card + '<form method="post" action="/admin">', 1)
    page += field('public_base_url', '订阅域名（包含 http:// 或 https://，不带路径）', c.get('public_base_url', DEFAULT_PUBLIC_URL))
    style = c.get('output_style', 'pools')
    page += '<label>订阅分组样式<select name="output_style"><option value="classic"' + (' selected' if style == 'classic' else '') + '>经典应用分组（与图 1 相同）</option><option value="pools"' + (' selected' if style == 'pools' else '') + '>CFOpt 业务与国家 Pool</option></select></label>'
    filenames = c.get('subscription_filenames', {})
    page += field('filename_default', '自动订阅文件名', filenames.get('default', 'yuanclash.yaml'))
    page += field('filename_cmcc', '移动订阅文件名', filenames.get('cmcc', '北京移动_yuanclash.yaml'))
    page += field('filename_ctc', '电信订阅文件名', filenames.get('ctc', '成都电信_yuanclash.yaml'))
    quota = c.get('request_quota_display', {})
    page += '<fieldset><legend>Clash Party 请求额度显示</legend><small>客户端只能显示流量单位；按下方比例将 UsagePanel 请求次数换算成 KB。默认 1000 次 = 1 KB，因此 70 万次显示为 700 KB。</small>'
    page += field('quota_total_requests', '面板不可用时的总请求次数', quota.get('total_requests', 700000), 'number')
    page += field('quota_requests_per_kib', '每 1 KB 代表的请求次数', quota.get('requests_per_kib', 1000), 'number')
    page += field('quota_expire', '显示到期时间（Unix 秒）', quota.get('expire', 4102329600), 'number') + '</fieldset>'
    page += field('node_uri', 'VLESS 节点 URI', c['node_uri'], 'password')
    page += field('rule_template_url', 'GitHub 路由模板 INI 地址（空白则使用原配置规则）', c.get('rule_template_url', ''))
    page += field('rule_cache_seconds', '规则缓存秒数（60–86400）', c.get('rule_cache_seconds', 300), 'number')
    page += '<small>INI、ruleset 与国家 Pool 按模板实时编译。下载失败保留上次完整成功快照。</small></fieldset><fieldset id="proxyip"><legend>国家 ProxyIP 链式节点</legend>'
    checked = 'checked' if c.get('proxyip_enabled', False) else ''
    page += f'<label><input type="checkbox" name="proxyip_enabled" {checked}> 生成指定国家 ProxyIP 节点</label>'
    page += field('proxyip_url', 'ProxyIP 池 HTTPS 地址', c.get('proxyip_url', DEFAULT_PROXYIP_URL))
    page += field('proxyip_per_country', '每个国家候选数量（1–50）', c.get('proxyip_per_country', 10), 'number')
    page += '<small>同国家 ↪；DE → IE/AT；GB → IE。入口 IP 是 CSV 测点结果，不代表出口国家。ProxyIP 列表写入 WS 路径，不仅是名称标记。候选池测速不等于所有业务解锁保证。</small></fieldset><fieldset id="hosts"><legend>Host 多选与账户关联</legend><table><tr><th>启用</th><th>域名</th><th>UsagePanel 账户 ID</th></tr>'
    hosts = c['hosts'] + [{'name': '', 'enabled': True}] * 3
    page += f'<input type="hidden" name="host_count" value="{len(hosts)}">'
    for i, h in enumerate(hosts):
        checked = 'checked' if h.get('enabled', True) else ''
        page += f'<tr><td><input type="checkbox" name="host_enabled_{i}" {checked}></td><td>' + field(f'host_name_{i}', '', h['name']) + '</td><td>' + field(f'host_account_{i}', '', h.get('usage_account', ''), 'number') + '</td></tr>'
    page += '</table></fieldset><fieldset><legend>优选 CSV 与地区匹配</legend><small>运营商填 CMCC / CTC / CUCC；地区留空表示不限。地区为查询服务地名子串。</small>'
    sources = c['sources'] + [{'name': '', 'url': '', 'default': True}] * 2
    page += f'<input type="hidden" name="source_count" value="{len(sources)}">'
    for i, s in enumerate(sources):
        page += '<fieldset>'
        for key, label in [('name', '名称'), ('url', 'HTTPS CSV 地址'), ('isp', '运营商'), ('region', '地区')]:
            page += field(f'source_{key}_{i}', label, s.get(key, ''))
        checked = 'checked' if s.get('default', True) else ''
        page += f'<label><input type="checkbox" name="source_default_{i}" {checked}> 未识别时采用此列表</label></fieldset>'
    page += '</fieldset><fieldset><legend>用量与请求者识别</legend>'
    page += field('usage_url', '用量 API（含私密 token）', c['usage_url'], 'password')
    page += field('usage_panel_url', 'UsagePanel 地址', c.get('usage_panel', {}).get('url', ''))
    page += field('usage_panel_cookie', '管理员 Cookie（留空保留现有凭据）', '', 'password')
    page += field('disable_gap', '停用用量差距（0–1）', c.get('disable_gap', .35), 'number').replace('type="number" name="disable_gap"', 'type="number" step="0.01" name="disable_gap"')
    page += field('geo_url', '公网 IP 查询 API（会向该服务发送请求者 IP；空白禁用）', c.get('geo_url', ''))
    page += field('trusted_proxies', '可信 Tunnel 来源 IP（逗号分隔）', ','.join(c.get('trusted_proxies', [])))
    page += '</fieldset><button>验证并保存配置</button></form><details><summary>高级 JSON 编辑（含敏感配置）</summary><form method="post" action="/admin"><textarea name="config" style="width:100%;height:400px">' + html.escape(json.dumps({k: v for k, v in c.items() if k not in ('admin_password', 'subscription_token')}, ensure_ascii=False, indent=2)) + '</textarea><p><button>验证并保存 JSON</button></p></form></details>'
    page = re.sub(r'<style>.*?</style>', '<style>' + ADMIN_CSS + '</style>', page, count=1, flags=re.S)
    page = page.replace('<h1>CFOpt 订阅管理</h1>', '<nav><a class="active" href="/admin">动态 EdgeTunnel</a><a href="/admin/custom">自建节点订阅</a><a href="#subscriptions">订阅地址</a><a href="#routing">节点与规则</a><a href="#proxyip">国家 ProxyIP</a><a href="#hosts">域名与用量</a><a href="#sources">优选 CSV</a><a href="#diagnostics">Pool 验证</a></nav><div class="eyebrow">PRIVATE NETWORK CONSOLE</div><h1>CFOpt 订阅管理</h1><div class="metrics"><div class="metric"><small>生成节点</small><span id="metric-nodes">—</span></div><div class="metric"><small>ProxyIP 链式节点</small><span id="metric-chains">—</span></div><div class="metric"><small>路由规则</small><span id="metric-rules">—</span></div><div class="metric"><small>策略组</small><span id="metric-groups">—</span></div></div>')
    page = page.replace('<fieldset><legend>订阅地址', '<fieldset id="subscriptions"><legend>订阅地址', 1).replace('<fieldset><legend>节点与远程', '<fieldset id="routing"><legend>节点与远程', 1).replace('<fieldset><legend>优选 CSV', '<fieldset id="sources"><legend>优选 CSV', 1)
    page += '<fieldset id="diagnostics"><legend>生成与 Pool 验证</legend><p id="status-message" role="status">等待检查</p><button id="refresh-status" type="button">重新验证</button><div class="status-box"><div id="pool-counts" class="pool-list"></div></div></fieldset>'
    return page


def custom_admin_page(c):
    settings = custom_defaults(c)
    def field(name, label, value='', kind='text', extra=''):
        return (f'<label>{html.escape(label)}<input type="{kind}" name="{name}" '
                f'value="{html.escape(str(value), quote=True)}" {extra}></label>')
    link = custom_subscription_link(c)
    page = ('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>自建节点订阅</title><style>' + ADMIN_CSS + '</style>'
            '<nav><a href="/admin">动态 EdgeTunnel</a><a class="active" href="/admin/custom">自建节点订阅</a>'
            '<a href="#custom-link">订阅地址</a><a href="#base-nodes">基础节点</a><a href="#custom-csv">优选 CSV</a>'
            '<a href="#custom-rules">分流规则</a><a href="#diagnostics">生成验证</a></nav>'
            '<div class="eyebrow">PRIVATE NETWORK CONSOLE</div><h1>自建节点订阅</h1>'
            '<p>把基础 VLESS WS TLS 节点展开为 JP、KR、HK、SG、TW 各 2 个优选入口；出口仍由你的基础节点决定。</p>'
            '<div class="metrics"><div class="metric"><small>生成节点</small><span id="metric-nodes">—</span></div>'
            '<div class="metric"><small>固定地区</small><span>5</span></div><div class="metric"><small>每区入口</small><span>2</span></div>'
            '<div class="metric"><small>策略组</small><span id="metric-groups">—</span></div></div>'
            '<fieldset id="custom-link"><legend>自建节点订阅地址</legend>'
            f'<label>可直接导入 Clash Party<input id="custom-subscription" readonly value="{html.escape(link, quote=True)}"></label>'
            '<button type="button" data-copy="custom-subscription">复制地址</button><p id="copy-result" role="status"></p>'
            '<small>固定槽位名称不会包含实时速度或 IP，CSV 更新后仍可保留 Clash 的手动选择。</small></fieldset>'
            '<form method="post" action="/admin/custom"><input type="hidden" name="mode" value="custom">')
    page += '<fieldset id="base-nodes"><legend>基础 VLESS WS TLS 节点</legend><small>server 和 port 将由 CSV 优选入口替换，不需要填写。支持以后添加多个基础节点。</small>'
    nodes = settings['nodes'] + [{'name': '', 'uuid': '', 'servername': '', 'path': '', 'enabled': True}] * 2
    page += f'<input type="hidden" name="custom_node_count" value="{len(nodes)}">'
    for i, node in enumerate(nodes):
        checked = 'checked' if node.get('enabled', True) else ''
        verify = 'checked' if node.get('skip_cert_verify', False) else ''
        page += f'<fieldset><legend>基础节点 {i + 1}</legend><div class="grid">'
        page += f'<label><input type="checkbox" name="custom_node_enabled_{i}" {checked}> 启用</label>'
        page += f'<label><input type="checkbox" name="custom_node_skip_{i}" {verify}> 跳过证书验证</label>'
        page += field(f'custom_node_name_{i}', '节点名称', node.get('name', ''))
        page += field(f'custom_node_uuid_{i}', 'UUID', node.get('uuid', ''), 'password')
        page += field(f'custom_node_servername_{i}', 'TLS Server Name / WS Host', node.get('servername', ''))
        page += field(f'custom_node_fingerprint_{i}', '客户端指纹', node.get('client_fingerprint', 'chrome'))
        page += '<div class="wide">' + field(f'custom_node_path_{i}', 'WebSocket Path', node.get('path', '')) + '</div>'
        page += '</div></fieldset>'
    page += '</fieldset><fieldset id="custom-csv"><legend>入口优选 CSV</legend>'
    page += '<small>合并所有列表后按地区去重。优先取速度超过阈值且 Ping 最低的 2 个；不足 2 个时回退为该地区 Ping 最低的 2 个。CSV 速度列单位是 MB/s。</small>'
    page += field('custom_speed_threshold', '速度阈值（MB/s）', settings['speed_threshold'], 'number', 'step="0.1" min="0"')
    sources = settings['sources'] + [{'name': '', 'url': ''}] * 2
    page += f'<input type="hidden" name="custom_source_count" value="{len(sources)}">'
    for i, source in enumerate(sources):
        page += '<div class="grid">' + field(f'custom_source_name_{i}', '列表名称', source.get('name', ''))
        page += field(f'custom_source_url_{i}', 'HTTPS CSV 地址', source.get('url', '')) + '</div>'
    page += '</fieldset><fieldset id="custom-rules"><legend>分流与文件名</legend>'
    page += field('custom_filename', '订阅文件名', settings['filename'])
    page += field('custom_rule_url', 'GitHub 路由模板 INI 地址', settings['rule_template_url'])
    page += field('custom_rule_cache', '规则缓存秒数（60–86400）', settings['rule_cache_seconds'], 'number')
    page += '<small>读取 INI 的域名/IP 分流规则，但不使用其中的国家匹配或自动测速 Pool。每个业务策略组都直接列出全部生成节点和 DIRECT，均为手动 select。</small>'
    page += '</fieldset><button>验证并保存自建节点配置</button></form>'
    page += ('<fieldset id="diagnostics"><legend>生成验证</legend><p id="status-message" data-endpoint="/admin/custom/status" role="status">等待检查</p>'
             '<button id="refresh-status" type="button">重新验证</button><div class="status-box"><div id="pool-counts" class="pool-list"></div></div></fieldset>'
             '<script src="/admin.js" defer></script>')
    return page


def form_custom_config(c, fields):
    new = copy.deepcopy(c)
    value = lambda key: fields.get(key, [''])[0].strip()
    nodes = []
    count = int(value('custom_node_count'))
    if not 1 <= count <= 64:
        raise ValueError('Too many custom nodes')
    for i in range(count):
        name = value(f'custom_node_name_{i}')
        if not name:
            continue
        nodes.append({'name': name, 'uuid': value(f'custom_node_uuid_{i}'),
                      'servername': value(f'custom_node_servername_{i}'),
                      'path': value(f'custom_node_path_{i}'),
                      'client_fingerprint': value(f'custom_node_fingerprint_{i}') or 'chrome',
                      'skip_cert_verify': f'custom_node_skip_{i}' in fields,
                      'enabled': f'custom_node_enabled_{i}' in fields})
    sources = []
    count = int(value('custom_source_count'))
    if not 1 <= count <= 64:
        raise ValueError('Too many custom sources')
    for i in range(count):
        url = value(f'custom_source_url_{i}')
        if not url:
            continue
        sources.append({'name': value(f'custom_source_name_{i}'), 'url': url})
    new['custom_subscription'] = {
        'filename': value('custom_filename'), 'speed_threshold': float(value('custom_speed_threshold')),
        'per_region': 2, 'rule_template_url': value('custom_rule_url'),
        'rule_cache_seconds': int(value('custom_rule_cache')), 'sources': sources, 'nodes': nodes,
    }
    validate_custom_settings(new)
    return new


def form_config(c, fields):
    new = copy.deepcopy(c)
    value = lambda k: fields.get(k, [''])[0].strip()
    new['public_base_url'] = public_base_url(fields.get('public_base_url', [c.get('public_base_url', DEFAULT_PUBLIC_URL)])[0])
    new['output_style'] = fields.get('output_style', [c.get('output_style', 'pools')])[0].strip()
    if new['output_style'] not in ('classic', 'pools'):
        raise ValueError('Unknown output style')
    existing_names = c.get('subscription_filenames', {})
    defaults = {'default': 'yuanclash.yaml', 'cmcc': '北京移动_yuanclash.yaml', 'ctc': '成都电信_yuanclash.yaml'}
    new['subscription_filenames'] = {key: fields.get('filename_' + key, [existing_names.get(key, defaults[key])])[0].strip() for key in defaults}
    for key in new['subscription_filenames']:
        subscription_filename(new, {'cmcc': 'CMCC', 'ctc': 'CTC'}.get(key, ''))
    previous_quota = c.get('request_quota_display', {})
    new['request_quota_display'] = {
        'total_requests': int(fields.get('quota_total_requests', [previous_quota.get('total_requests', 700000)])[0]),
        'requests_per_kib': int(fields.get('quota_requests_per_kib', [previous_quota.get('requests_per_kib', 1000)])[0]),
        'expire': int(fields.get('quota_expire', [previous_quota.get('expire', 4102329600)])[0]),
    }
    subscription_userinfo({**new, 'usage_panel': {}})
    if 'proxyip_url' in fields:
        new['proxyip_enabled'] = 'proxyip_enabled' in fields
        new['proxyip_url'] = value('proxyip_url')
        new['proxyip_per_country'] = int(value('proxyip_per_country'))
        if not 1 <= new['proxyip_per_country'] <= 50:
            raise ValueError('ProxyIP count out of range')
    for key in ('node_uri', 'usage_url', 'rule_template_url', 'geo_url'):
        new[key] = value(key)
    new['rule_cache_seconds'] = int(value('rule_cache_seconds'))
    new['disable_gap'] = float(value('disable_gap'))
    if not 60 <= new['rule_cache_seconds'] <= 86400 or not 0 <= new['disable_gap'] <= 1:
        raise ValueError('Threshold out of range')
    new['trusted_proxies'] = [str(ipaddress.ip_address(p.strip())) for p in value('trusted_proxies').split(',') if p.strip()]
    panel = new.setdefault('usage_panel', {})
    panel['url'] = value('usage_panel_url')
    if value('usage_panel_cookie'):
        panel['admin_cookie'] = value('usage_panel_cookie')
    if not panel['url']:
        new.pop('usage_panel')
    new['hosts'], new['sources'] = [], []
    host_count, source_count = int(value('host_count')), int(value('source_count'))
    if not 1 <= host_count <= 64 or not 1 <= source_count <= 64:
        raise ValueError('Too many entries')
    for i in range(host_count):
        name = value(f'host_name_{i}')
        if not name:
            continue
        if not re.fullmatch(r'[a-zA-Z0-9.-]+', name) or name in [h['name'] for h in new['hosts']]:
            raise ValueError('Invalid/duplicate host')
        h = {'name': name, 'enabled': f'host_enabled_{i}' in fields}
        if value(f'host_account_{i}'):
            h['usage_account'] = int(value(f'host_account_{i}'))
        new['hosts'].append(h)
    for i in range(source_count):
        url = value(f'source_url_{i}')
        if not url:
            continue
        new['sources'].append({k: value(f'source_{k}_{i}') for k in ('name', 'url', 'isp', 'region')} | {'default': f'source_default_{i}' in fields})
    return new


def fetch(url, ttl=300, headers=None):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname:
        raise ValueError('Sources must use HTTPS')
    cache_key = (url, hashlib.sha256(json.dumps(headers or {}, sort_keys=True).encode()).hexdigest())
    with LOCK:
        item = CACHE.get(cache_key)
        if item and time.time() - item[0] < ttl:
            return item[1]
    req = urllib.request.Request(url, headers={'User-Agent': 'CFOpt-Subscription/1.0', **(headers or {})})
    with urllib.request.urlopen(req, timeout=12) as r:
        data = r.read(4 * 1024 * 1024 + 1)
    if len(data) > 4 * 1024 * 1024:
        raise ValueError('Source too large')
    with LOCK:
        CACHE[cache_key] = (time.time(), data)
    return data


def config():
    with LOCK:
        return json.loads((ROOT / 'config.json').read_text())


def usage_json(url, headers=None, expected_type=dict):
    # Serialise refreshes so simultaneous subscriptions share one result.
    key = (url, hashlib.sha256(json.dumps(headers or {}, sort_keys=True).encode()).hexdigest())
    with USAGE_LOCK:
        now = time.monotonic()
        item = USAGE_CACHE.get(key)
        if item and now - item[0] < USAGE_CACHE_SECONDS:
            return copy.deepcopy(item[1])
        if now < USAGE_RETRY_AFTER.get(key, 0):
            raise ValueError('Usage refresh is in retry cooldown')
        try:
            # Only validated JSON enters the hour cache. Invalid HTML/JSON
            # must be fetched again after the five-minute cooldown.
            raw = fetch(url, 0, headers=headers) if headers else fetch(url, 0)
            data = json.loads(raw)
            if not isinstance(data, expected_type):
                raise ValueError('Invalid usage response')
        except Exception:
            USAGE_RETRY_AFTER[key] = time.monotonic() + USAGE_RETRY_SECONDS
            raise
        USAGE_CACHE[key] = (time.monotonic(), data)
        USAGE_RETRY_AFTER.pop(key, None)
        return copy.deepcopy(data)


def panel_accounts(c):
    panel = c.get('usage_panel')
    if not panel:
        return []
    # Public usage request performs the panel's normal throttled refresh; never force.
    usage_json(c['usage_url'])
    data = usage_json(panel['url'].rstrip('/') + '/admin/config.json',
                      headers={'Cookie': 'admin_token=' + panel['admin_cookie']}, expected_type=list)
    if not isinstance(data, list):
        raise ValueError('UsagePanel did not return account data')
    return data


def subscription_userinfo(c):
    display = c.get('request_quota_display', {})
    requests_per_kib = int(display.get('requests_per_kib', 1000))
    fallback_total = int(display.get('total_requests', 700000))
    expire = int(display.get('expire', 4102329600))
    if not 1 <= requests_per_kib <= 1000000 or fallback_total < 0 or expire < 0:
        raise ValueError('Invalid request quota display')
    used, total = 0, fallback_total
    try:
        wanted = {str(h['usage_account']) for h in c.get('hosts', []) if h.get('usage_account') is not None}
        accounts = [a for a in panel_accounts(c) if not wanted or str(a.get('ID')) in wanted]
        values = []
        for account in accounts:
            usage = account.get('Usage', {})
            account_used, account_total = int(usage['total']), int(usage['max'])
            if usage.get('success') and account_used >= 0 and account_total > 0:
                values.append((account_used, account_total))
        if values:
            used, total = sum(v[0] for v in values), sum(v[1] for v in values)
    except Exception:
        pass
    # Clash only supports byte traffic. Here one displayed KiB represents a
    # configurable number of requests; this is quota telemetry, not bandwidth.
    to_bytes = lambda requests: round(requests / requests_per_kib * 1024)
    return f'upload={to_bytes(used)}; download=0; total={to_bytes(total)}; expire={expire}'


def host_weights(c):
    usage = {}
    try:
        data = usage_json(c['usage_url'])
        # Explicit host keyed contract only; account totals are NOT host usage.
        for host, value in data.get('hosts', {}).items():
            if isinstance(value, dict):
                stamp = value.get('updated_at', data.get('updated_at', 0))
                if stamp > 1e12:
                    stamp /= 1000
                if not stamp or abs(time.time() - stamp) > USAGE_CACHE_SECONDS + 1800:
                    continue
                used, limit = float(value['used']), float(value['limit'])
                if used >= 0 and limit > 0:
                    usage[host] = used / limit
    except Exception:
        pass
    accounts = []
    try:
        accounts = panel_accounts(c)
    except Exception:
        pass
    by_id = {str(a.get('ID')): a for a in accounts}
    for host in c['hosts']:
        account = by_id.get(str(host.get('usage_account', '')))
        if not account:
            continue
        value = account.get('Usage', {})
        stamp = float(account.get('UpdateTime', 0)) / 1000
        try:
            used, limit = float(value['total']), float(value['max'])
            if value.get('success') and 0 <= time.time() - stamp <= USAGE_CACHE_SECONDS + 1800 and used >= 0 and limit > 0:
                usage[host['name']] = used / limit
        except (ValueError, KeyError, TypeError):
            continue
    hosts = [h for h in c['hosts'] if h.get('enabled', True)]
    if not hosts:
        raise ValueError('No enabled hosts')
    # Missing usage falls back to equal weight, not zero usage.
    minimum = min((usage[h['name']] for h in hosts if h['name'] in usage), default=0)
    result = []
    shares = {}
    for h in hosts:
        account_id = str(h.get('usage_account', ''))
        if account_id:
            shares[account_id] = shares.get(account_id, 0) + 1
    for h in hosts:
        ratio = usage.get(h['name'])
        weight = 1 if ratio is None else max(.05, 1 - ratio) ** 2
        if ratio is not None and (ratio >= .95 or ratio - minimum >= c.get('disable_gap', .35)):
            weight = 0
        if ratio is not None and h.get('usage_account'):
            weight /= shares[str(h['usage_account'])]
        result.append((h, weight))
    if not any(w for _, w in result):
        raise ValueError('All hosts above usage threshold')
    return result, any(h['name'] in usage for h in hosts)


def country(name):
    m = re.search(r'\b(HK|TW|JP|KR|SG|US|DE|GB|IE|AT|PH|VN|MY|KZ|MN|NL)\b', name)
    return m.group(1) if m else ''


def endpoint(value):
    value = str(value or '').strip().lower().rstrip('.')
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        try:
            ascii_name = value.encode('idna').decode('ascii')
        except UnicodeError as error:
            raise ValueError('Invalid endpoint') from error
        labels = ascii_name.split('.')
        if (len(ascii_name) > 253 or len(labels) < 2 or
                any(not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label) for label in labels)):
            raise ValueError('Invalid endpoint')
        return ascii_name


def custom_defaults(c):
    configured = c.get('custom_subscription', {})
    sources = configured.get('sources')
    if sources is None:
        sources = [{'name': s.get('name', 'CSV'), 'url': s.get('url', '')}
                   for s in c.get('sources', []) if s.get('url')]
    return {
        'filename': configured.get('filename', '自建节点.yaml'),
        'speed_threshold': configured.get('speed_threshold', 10),
        'per_region': configured.get('per_region', 2),
        'rule_template_url': configured.get('rule_template_url', c.get('rule_template_url', DEFAULT_RULE_URL)),
        'rule_cache_seconds': configured.get('rule_cache_seconds', c.get('rule_cache_seconds', 300)),
        'sources': sources,
        'nodes': configured.get('nodes', []),
    }


def validate_custom_settings(c):
    settings = custom_defaults(c)
    filename = str(settings['filename']).strip()
    if (not filename.lower().endswith(('.yaml', '.yml')) or not 1 <= len(filename) <= 120 or
            re.search(r'[\\/:*?"<>|\x00-\x1f]', filename)):
        raise ValueError('Invalid custom subscription filename')
    threshold = float(settings['speed_threshold'])
    per_region = int(settings['per_region'])
    ttl = int(settings['rule_cache_seconds'])
    if not 0 <= threshold <= 100000 or per_region != 2 or not 60 <= ttl <= 86400:
        raise ValueError('Invalid custom selection settings')
    if not settings['rule_template_url']:
        raise ValueError('Custom rule URL required')
    if not settings['sources'] or len(settings['sources']) > 64:
        raise ValueError('Custom CSV sources required')
    for source in settings['sources']:
        if not str(source.get('name', '')).strip() or not str(source.get('url', '')).strip():
            raise ValueError('Custom CSV name and URL required')
    enabled = [n for n in settings['nodes'] if n.get('enabled', True)]
    if not enabled or len(settings['nodes']) > 64:
        raise ValueError('At least one custom base node required')
    names = set()
    for node in enabled:
        name = str(node.get('name', '')).strip()
        uuid = str(node.get('uuid', '')).strip()
        sni = endpoint(node.get('servername', ''))
        path = str(node.get('path', '')).strip()
        if not name or len(name) > 80 or name in names or not re.fullmatch(r'[0-9a-fA-F-]{32,36}', uuid):
            raise ValueError('Invalid custom node name or UUID')
        if not path.startswith('/') or any(ord(ch) < 32 for ch in path):
            raise ValueError('Invalid custom WS path')
        names.add(name)
        node['name'], node['uuid'], node['servername'], node['path'] = name, uuid, sni, path
    settings.update({'filename': filename, 'speed_threshold': threshold, 'per_region': per_region,
                     'rule_cache_seconds': ttl})
    return settings


def select_custom_endpoints(settings):
    candidates = {region: [] for region in CUSTOM_REGIONS}
    failed = []
    for source in settings['sources']:
        try:
            rows = csv.DictReader(io.StringIO(fetch(source['url']).decode('utf-8-sig')))
            for row in rows:
                region = country(row.get('城市', ''))
                if region not in candidates or row.get('TLS', '').lower() != 'true':
                    continue
                address = endpoint(row.get('IP地址', ''))
                port = int(row.get('端口', 0))
                latency = float(row.get('平均延迟', ''))
                speed = float(row.get('下载速度(MB/s)', ''))
                if 1 <= port <= 65535 and latency >= 0 and speed >= 0:
                    candidates[region].append({'server': address, 'port': port, 'latency': latency,
                                               'speed': speed, 'source': source['name']})
        except Exception:
            failed.append(source['name'])
    selected = {}
    for region, rows in candidates.items():
        unique = {}
        for row in rows:
            key = (row['server'], row['port'])
            if key not in unique or (row['latency'], -row['speed']) < (unique[key]['latency'], -unique[key]['speed']):
                unique[key] = row
        all_rows = sorted(unique.values(), key=lambda x: (x['latency'], -x['speed'], x['server'], x['port']))
        fast = [row for row in all_rows if row['speed'] > settings['speed_threshold']]
        selected[region] = (fast if len(fast) >= settings['per_region'] else all_rows)[:settings['per_region']]
        if len(selected[region]) < settings['per_region']:
            raise ValueError('Not enough custom endpoints for ' + region)
    return selected, failed


def custom_routing(settings, nodes):
    url = settings['rule_template_url']
    ttl = settings['rule_cache_seconds']
    snapshot = ROOT / ('custom-routing-' + hashlib.sha256(url.encode()).hexdigest() + '.json')
    stale = False
    try:
        routing = compile_ini(fetch(url, ttl).decode('utf-8-sig'), lambda u: fetch(u, ttl).decode('utf-8-sig'))
        with LOCK:
            temp = snapshot.with_suffix('.tmp')
            temp.write_text(json.dumps(routing, ensure_ascii=False), encoding='utf-8')
            os.chmod(temp, 0o600)
            os.replace(temp, snapshot)
    except Exception:
        if not snapshot.exists():
            raise
        routing = json.loads(snapshot.read_text(encoding='utf-8'))
        stale = True
    policies = set(routing.get('policies', []))
    ordered = [parts[0] for parts in routing['definitions'] if parts[0] in policies]
    ordered.extend(policy for policy in routing.get('policies', []) if policy not in ordered and policy not in ('DIRECT', 'REJECT'))
    names = [node['name'] for node in nodes]
    groups = []
    for name in ordered:
        if name in ('DIRECT', 'REJECT', 'Direct'):
            continue
        choices = (['DIRECT'] + names) if name.lower() == 'direct' else (names + ['DIRECT'])
        groups.append({'name': name, 'type': 'select', 'proxies': choices})
    # Rules may target Direct as a policy group in the source INI. Keep it a
    # selectable group as requested, with DIRECT as the safe default.
    if 'Direct' in policies:
        groups.append({'name': 'Direct', 'type': 'select', 'proxies': ['DIRECT'] + names})
    valid = {g['name'] for g in groups} | {'DIRECT', 'REJECT'}
    def rule_policy(rule):
        parts = rule.split(',')
        return parts[1] if parts[0] in ('MATCH', 'FINAL') else parts[2]
    if any(rule_policy(rule) not in valid for rule in routing['rules']):
        raise ValueError('Custom routing contains an unavailable policy')
    return groups, routing['rules'], stale


def build_custom(c):
    settings = validate_custom_settings(c)
    selected, failed = select_custom_endpoints(settings)
    nodes = []
    for base_node in settings['nodes']:
        if not base_node.get('enabled', True):
            continue
        for region in CUSTOM_REGIONS:
            for slot, candidate in enumerate(selected[region], 1):
                nodes.append({
                    'name': f"{base_node['name']} · {FLAGS[region]} {region} 优选 {slot}",
                    'type': 'vless', 'server': candidate['server'], 'port': candidate['port'],
                    'uuid': base_node['uuid'], 'tls': True,
                    'skip-cert-verify': bool(base_node.get('skip_cert_verify', False)),
                    'servername': base_node['servername'],
                    'client-fingerprint': base_node.get('client_fingerprint', 'chrome') or 'chrome',
                    'network': 'ws', 'ws-opts': {'path': base_node['path'],
                                                 'headers': {'Host': base_node['servername']}},
                })
    groups, rules, stale = custom_routing(settings, nodes)
    try:
        result = json.loads((ROOT / 'template.json').read_text())
    except Exception:
        result = {}
    result['proxies'], result['proxy-groups'], result['rules'] = nodes, groups, rules
    counts = {group['name']: len(nodes) for group in groups}
    selected_status = [{'region': region, 'count': len(rows),
                        'entries': [{'server': r['server'], 'port': r['port'], 'latency': r['latency'],
                                     'speed': r['speed'], 'source': r['source']} for r in rows]}
                       for region, rows in selected.items()]
    return result, {'nodes': len(nodes), 'rules': len(rules), 'pool_counts': counts,
                    'selected_entries': selected_status, 'failed_sources': failed, 'rules_stale': stale}


def build(c, isp='', region='', seed='', output_style=''):
    template = json.loads((ROOT / 'template.json').read_text())
    old = {n['name']: n for n in template['proxies']}
    sources = c['sources']
    matched = [s for s in sources if (s.get('isp') or s.get('region')) and
               (not s.get('isp') or s['isp'] == isp) and
               (not s.get('region') or s['region'] in region)]
    sources = matched or [s for s in sources if s.get('default', True)]
    weights, dynamic = host_weights(c)
    totals = [0.0] * len(weights)
    nodes, seen, errors = [], set(), []
    uri = urllib.parse.urlsplit(c['node_uri'])
    q = dict(urllib.parse.parse_qsl(uri.query))
    if uri.scheme != 'vless' or not uri.username or q.get('type') != 'ws' or q.get('security') != 'tls':
        raise ValueError('Only VLESS WS TLS supported')
    for source in sources:
        try:
            text = fetch(source['url']).decode('utf-8-sig')
            rows = list(csv.DictReader(io.StringIO(text)))
        except Exception:
            errors.append(source['name'])
            continue
        for row in rows[:c.get('max_nodes_per_source', 500)]:
            try:
                address = endpoint(row['IP地址'])
                port = int(row['端口'])
                if not 1 <= port <= 65535 or row.get('TLS', '').lower() != 'true':
                    continue
            except (ValueError, KeyError):
                continue
            key = (address, port)
            if key in seen:
                continue
            seen.add(key)
            for i, (_, w) in enumerate(weights):
                totals[i] += w
            i = max(range(len(weights)), key=lambda j: totals[j])
            totals[i] -= sum(w for _, w in weights)
            host = weights[i][0]['name']
            label = row.get('城市', address)
            code = country(label)
            measurement = re.search(r'\[[^\]]+\]', label)
            detail = measurement.group(0) if measurement else '[' + source['name'] + ']'
            name = f"{FLAGS.get(code, '')} {code} {detail} [{source['name']}] #{len(nodes)+1}".strip() if code else f"{label} [{source['name']}] #{len(nodes)+1}"
            node = {'name': name, 'type': 'vless', 'server': address, 'port': port,
                    'uuid': uri.username, 'tls': True, 'skip-cert-verify': False,
                    'servername': host, 'client-fingerprint': q.get('fp', 'chrome'),
                    'network': 'ws', 'ws-opts': {'path': q.get('path', '/'), 'headers': {'Host': host}}}
            if q.get('ech'):
                node['ech-opts'] = {'enable': True, 'query-server-name': q['ech'].split('+')[0]}
            nodes.append(node)
    if not nodes:
        raise ValueError('No usable CSV nodes; old subscription should be retained')
    nodes, chain_status = add_chains(c, nodes)
    names = [n['name'] for n in nodes]
    groups = template['proxy-groups']
    valid = {g['name'] for g in groups} | {'DIRECT', 'REJECT'}
    for g in groups:
        refs = g.get('proxies', [])
        oldrefs = [old[r] for r in refs if r in old]
        countries = {country(n['name']) for n in oldrefs} - {''}
        keep = [r for r in refs if r in valid]
        if oldrefs:
            selected = [n['name'] for n in nodes if country(n['name']) in countries] if countries and len(countries) <= 2 else names
            keep += selected or ['REJECT']
        g['proxies'] = list(dict.fromkeys(keep or ['DIRECT']))
    template['proxies'] = nodes
    routing_status = {'rule_template_url': '', 'rules_stale': False, 'empty_groups': []}
    style = output_style or c.get('output_style', 'pools')
    if style == 'classic':
        template['proxy-groups'], template['rules'], routing_status = classic_routing(nodes)
    elif style == 'pools' and c.get('rule_template_url'):
        template['proxy-groups'], template['rules'], routing_status = remote_routing(c, nodes)
    elif style != 'pools':
        raise ValueError('Unknown output style')
    return template, {**routing_status, **chain_status, 'rules': len(template['rules']), 'nodes': len(nodes), 'dynamic_usage': dynamic, 'sources': [s['name'] for s in sources], 'failed_sources': errors,
                      'host_counts': {h['name']: sum(n['servername'] == h['name'] for n in nodes) for h, _ in weights}}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log token URLs, client addresses, or credentials.

    def reply(self, status, body, mime='application/json', headers=None):
        data = body.encode() if isinstance(body, str) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', mime + '; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'")
        self.send_header('Referrer-Policy', 'no-referrer')
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def admin(self, c):
        expect = 'Basic ' + base64.b64encode(('admin:' + c['admin_password']).encode()).decode()
        if hmac.compare_digest(self.headers.get('Authorization', ''), expect):
            return True
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="CFOpt admin"')
        self.end_headers()
        return False

    def do_GET(self):
        c = config()
        url = urllib.parse.urlsplit(self.path)
        query = dict(urllib.parse.parse_qsl(url.query))
        route = url.path.strip('/').split('/')
        path_subscription = len(route) == 5 and route[:2] == ['admin', 'sub']
        path_status = len(route) == 5 and route[:2] == ['admin', 'status']
        path_token = urllib.parse.unquote(route[2]) if path_subscription or path_status else ''
        path_isp = route[3] if path_subscription or path_status else ''
        path_style = route[4] if path_subscription or path_status else ''
        custom_subscription = len(route) == 4 and route[:3] == ['admin', 'custom', 'sub']
        custom_token = urllib.parse.unquote(route[3]) if custom_subscription else ''
        if url.path == '/health':
            return self.reply(200, {'ok': True})
        if url.path == '/admin.js':
            if not self.admin(c):
                return
            return self.reply(200, ADMIN_JS, 'application/javascript')
        if url.path == '/admin':
            if not self.admin(c):
                return
            return self.reply(200, admin_page(c), 'text/html')
        if url.path == '/admin/custom':
            if not self.admin(c):
                return
            return self.reply(200, custom_admin_page(c), 'text/html')
        if url.path == '/admin/custom/status':
            if not self.admin(c):
                return
            try:
                _, status = build_custom(c)
                return self.reply(200, status)
            except Exception:
                return self.reply(503, {'error': 'Custom generation failed'})
        if custom_subscription:
            if not hmac.compare_digest(custom_token, c['subscription_token']):
                return self.reply(404, {'error': 'Not found'})
            try:
                result, _ = build_custom(c)
                filename = validate_custom_settings(c)['filename']
                quoted = urllib.parse.quote(filename)
                ascii_name = re.sub(r'[^A-Za-z0-9._-]', '_', filename) or 'custom-nodes.yaml'
                headers = {'Content-Disposition': f"attachment; filename=\"{ascii_name}\"; filename*=UTF-8''{quoted}",
                           'profile-title': urllib.parse.quote(filename.rsplit('.', 1)[0]),
                           'Subscription-Userinfo': subscription_userinfo(c)}
                return self.reply(200, result, headers=headers)
            except Exception:
                return self.reply(503, {'error': 'Generation failed; keep existing profile and check configuration/sources'})
        admin_status = url.path == '/admin/status'
        if admin_status and not self.admin(c):
            return
        legacy_subscription = url.path in ('/sub', '/status') and hmac.compare_digest(query.get('token', ''), c['subscription_token'])
        routed_subscription = (path_subscription or path_status) and hmac.compare_digest(path_token, c['subscription_token'])
        if not admin_status and not (legacy_subscription or routed_subscription):
            return self.reply(404, {'error': 'Not found'})
        # Forwarded headers are trusted only from explicitly configured tunnel peers.
        client = self.client_address[0]
        if client in c.get('trusted_proxies', []):
            client = self.headers.get('CF-Connecting-IP', client)
        isp, region = '', ''
        try:
            if ipaddress.ip_address(client).is_global and c.get('geo_url'):
                geo = json.loads(fetch(c['geo_url'].replace('{ip}', urllib.parse.quote(client, safe=''))))
                connection = geo.get('connection', geo)
                label = str(connection.get('isp', '')) + str(connection.get('org', ''))
                region = str(geo.get('regionName', geo.get('region', '')))
                for tag, aliases in c.get('isp_aliases', {}).items():
                    if any(a.lower() in label.lower() for a in aliases):
                        isp = tag
                        break
        except Exception:
            pass
        # Explicit route overrides are available to subscription-token holders.
        try:
            selected_isp = query.get('isp', isp) if not routed_subscription else ('' if path_isp == 'AUTO' else path_isp)
            selected_style = query.get('style', '') if not routed_subscription else path_style
            result, status = build(c, selected_isp, query.get('region', region), client, selected_style)
            if url.path in ('/status', '/admin/status') or path_status:
                return self.reply(200, status)
            filename = subscription_filename(c, selected_isp)
            quoted = urllib.parse.quote(filename)
            ascii_name = re.sub(r'[^A-Za-z0-9._-]', '_', filename) or 'yuanclash.yaml'
            headers = {'Content-Disposition': f"attachment; filename=\"{ascii_name}\"; filename*=UTF-8''{quoted}",
                       'profile-title': urllib.parse.quote(filename.rsplit('.', 1)[0]),
                       'Subscription-Userinfo': subscription_userinfo(c)}
            return self.reply(200, result, headers=headers)
        except Exception:
            return self.reply(503, {'error': 'Generation failed; keep existing profile and check configuration/sources'})

    def do_POST(self):
        c = config()
        if self.path not in ('/admin', '/admin/custom') or not self.admin(c):
            return
        origin = self.headers.get('Origin', '')
        if not allowed_admin_origin(c, origin, self.headers.get('Host', '')):
            return self.reply(403, {'error': 'Cross-origin write rejected'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 65536:
                raise ValueError()
            fields = urllib.parse.parse_qs(self.rfile.read(length).decode())
            if self.path == '/admin/custom':
                new = form_custom_config(c, fields)
            else:
                new = form_config(c, fields) if fields.get('mode') == ['form'] else json.loads(fields['config'][0])
            if new.get('public_base_url'):
                new['public_base_url'] = public_base_url(new['public_base_url'])
            new['admin_password'], new['subscription_token'] = c['admin_password'], c['subscription_token']
            if self.path == '/admin/custom':
                build_custom(new)
            else:
                build(new)  # Validate before replacing known-good config.
            with LOCK:
                temp = ROOT / 'config.json.tmp'
                temp.write_text(json.dumps(new, ensure_ascii=False, indent=2))
                os.chmod(temp, 0o600)
                os.replace(temp, ROOT / 'config.json')
            self.reply(200, '保存成功。返回 /admin 继续编辑。', 'text/plain')
        except Exception:
            self.reply(400, {'error': 'Invalid configuration or unavailable sources; previous config preserved'})


if __name__ == '__main__':
    ThreadingHTTPServer((os.environ.get('CFOPT_BIND', '192.168.0.2'), int(os.environ.get('CFOPT_PORT', '8787'))), Handler).serve_forever()
