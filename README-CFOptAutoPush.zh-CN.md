# CFOpt 閼奉亜濮╁ù瀣偓鐔剁瑢閹恒劑鈧?
鏉╂瑥顨滈懘姘拱娴兼俺鍤滈崝銊ょ瑓鏉?`ip.zip`閿涘本瀵滄径姘嚋缁旑垰褰涢獮鎯邦攽濞村鈧噦绱濋崥鍫濊嫙缂佹挻鐏夐敍宀冪箖濠娿倓绗夐崣顖滄暏閹存牠鐝鎯扮箿閼哄倻鍋ｉ敍宀€鍔ч崥搴㈠Ω閺堚偓缂?CSV 娑撳﹣绱堕崚?`GuardSkill/CFOpt`閵?
## 娑撳﹣绱堕弬鍥︽

- Windows/CD 姒涙顓绘稉濠佺炊閿涙瓪CloudflareSpeedTest_CD.csv`
- Linux/BJ 姒涙顓绘稉濠佺炊閿涙瓪CloudflareSpeedTest_BJ.csv`
- 鐠併垽妲勬潪顒佸床闁板秶鐤嗛敍姝欳FOpt_Subconverter.ini`

## 閺佺増宓佸ù浣衡柤

1. 娑撳娴?`https://zip.cm.edu.kg/ip.zip`
2. 鐟欙絽甯囬獮鎯邦嚢閸欐牕顦挎稉顏嗩伂閸欙絿娲拌ぐ鏇礉姒涙顓?`443`閵嗕梗2053`閵嗕梗2083`閵嗕梗2087`閵嗕梗2096`閵嗕梗8443`
3. 濮ｅ繋閲滅粩顖氬經閸掑棗鍩嗛崥鍫濊嫙閹稿洤鐣鹃崶钘夘啀/閸︽澘灏弬鍥︽閿涘奔绶ユ俊?`HK.txt`閵嗕梗KR.txt`閵嗕梗SG.txt`
4. 濮ｅ繋閲滅粩顖氬經閻㈢喐鍨氶悪顒傜彌閻?IP 閸掓澘娴楃€?閸︽澘灏弰鐘茬殸閿涘奔绶ユ俊?`selected-ip-city-map-443.csv`
5. 濮ｅ繋閲滅粩顖氬經閸氼垰濮╂稉鈧稉?`cfst` 鏉╂稓鈻奸敍灞借嫙鐞涘本绁撮柅?6. 閸氬牆鑻熼幍鈧張澶岊伂閸欙絿娈?CSV 缂佹挻鐏?7. 鏉╁洦鎶ゆ稉宥呭讲閻劍鍨ㄦ妯烘鏉╃喓绮ㄩ弸?8. 濮ｅ繋閲滈崶钘夘啀/閸︽澘灏張鈧径姘箽閻?Top 20閿涘奔绱崗鍫滅瑓鏉炰粙鈧喎瀹抽弴鎾彯閿涘苯鍙惧▎鈥抽挬閸у洤娆㈡潻鐔告纯娴?9. 鏉堟挸鍤?edgetunnel 閸忕厧顔愰崚妤嬬窗`IP閸︽澘娼僠閵嗕梗缁旑垰褰沗閵嗕梗閺佺増宓佹稉顓炵妇`閵嗕梗閸╁骸绔禶閵嗕梗TLS`
10. 娑撳﹣绱堕崚?GitHub

閺堚偓缂佸牐濡悙鐟邦槵濞夈劋绱扮猾璁虫妧閿?
```text
198.41.223.63:2096#SG [86ms 76.20Mbps]
```

## 姒涙顓绘潻鍥ㄦ姢鐟欏嫬鍨?
- 娣囨繄鏆€ `瀹稿弶甯撮弨?>= 1`
- 娣囨繄鏆€ `娑撱垹瀵橀悳?< 1`
- 娣囨繄鏆€ `楠炲啿娼庡鎯扮箿 <= 420`
- 娣囨繄鏆€ `娑撳娴囬柅鐔峰 >= 0.01 Mbps`閿涘矂浼╅崗?0.00 闁喓绮ㄩ弸婊嗙箻閸忋儴顓归梼?- 濮ｅ繋閲滈崶钘夘啀/閸︽澘灏張鈧径姘箽閻?`20` 閺夆槄绱濈捄銊﹀閺堝绁寸拠鏇狀伂閸欙絼绔寸挧閿嬪笓閸?
娑撳瓨妞傜拫鍐╂殻瀵ゆ儼绻滈梼鍫濃偓纭风窗

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -MaxLatencyMs 300
```

```bash
FORCE=1 MAX_LATENCY_MS=300 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

婵″倹鐏夌紒鎾寸亯閸忋劍妲?`0.00 MB/s`閿涘瞼鏁?cfst 鐠嬪啳鐦Ο鈥崇础閹烘帗鐓℃稉瀣祰濞村鈧喎婀撮崸鈧妴涓 閹存牜缍夌紒婊堟６妫版﹫绱?
```bash
FORCE=1 CFST_DEBUG=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDebug
```

## Windows 娴ｈ法鏁?
姒涙顓荤捄顖氱窞閿?
```text
H:\PyProjects\cfst_windows_amd64\cfst.exe
H:\PyProjects\CFOptAutoPush
```

閸欘亙绗呮潪濮愨偓浣叫掗崢瀣ㄢ偓浣稿櫙婢跺洩绶崗銉礉娑撳秵绁撮柅鐔粹偓浣风瑝娑撳﹣绱堕敍?
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -DryRun
```

閻㈢喐鍨?CSV 娴ｅ棔绗夋稉濠佺炊閿?
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -SkipUpload
```

姒涙顓绘径姘鳖伂閸欙絽鑻熺悰灞剧ゴ闁喎鑻熸稉濠佺炊閿?
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force
```

閹稿洤鐣炬稉鈧紒鍕伂閸欙綇绱?
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -Ports "443,2053,2083,2087,2096,8443"
```

娑撳瓨妞傞崣顏呯ゴ閸楁洜顏崣锝忕窗

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -Port 8443
```

## Linux 娴ｈ法鏁?
娑撯偓鐞涘苯鐣ㄧ憗鍛嫙缁斿宓嗘潻鎰攽閿?
```bash
GITHUB_TOKEN_CFOPT="娴ｇ姷娈?token" bash -c "$(curl -fsSL https://raw.githubusercontent.com/GuardSkill/CFOpt/main/scripts/linux/install-and-run-cfopt-linux.sh)"
```

婵″倹鐏夊鑼病閸︺劋绮ㄦ惔鎾舵窗瑜版洟鍣烽敍灞藉涧閺勵垱鍏傞幍瀣З缁斿宓嗛弴瀛樻煀娑撯偓濞嗏槄绱濋悽顭掔窗

```bash
FORCE=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

閸戝棗顦?`cfst`閿?
```bash
mkdir -p "$HOME/cfopt-auto-push"
cp ./cfst "$HOME/cfopt-auto-push/cfst"
chmod +x "$HOME/cfopt-auto-push/cfst"
chmod +x ./scripts/linux/invoke-cfopt-auto-push-linux.sh
export GITHUB_TOKEN_CFOPT="娴ｇ姷娈?token"
```

姒涙顓绘径姘鳖伂閸欙絽鑻熺悰灞剧ゴ闁喎鑻熸稉濠佺炊閿?
```bash
FORCE=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

閻㈢喐鍨?CSV 娴ｅ棔绗夋稉濠佺炊閿?
```bash
FORCE=1 SKIP_UPLOAD=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

閹稿洤鐣剧粩顖氬經閸掓銆冮敍?
```bash
FORCE=1 PORTS="443,2053,2083,2087,2096,8443" ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

娑撳瓨妞傞崣顏呯ゴ閸楁洜顏崣锝忕窗

```bash
FORCE=1 PORT=8443 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

鐢摜鏁ら悳顖氼暔閸欐﹢鍣洪敍?
```bash
WORK_DIR="$HOME/cfopt-auto-push"
CFST_PATH="$HOME/cfopt-auto-push/cfst"
PORTS="443,2053,2083,2087,2096,8443"
TARGET_PATH="CloudflareSpeedTest_BJ.csv"
INTERVAL_DAYS=3
MAX_LATENCY_MS=420
MIN_SPEED_MBPS=0.01
MAX_PER_CITY=20
COUNTRIES_CSV="HK,KR,SG,PH,VN,MY,KZ,MN,IE,US"
```

## 缁旑垰褰涚拠瀛樻

`ip.zip` 闁插矂娼板鑼病閹稿顏崣锝呭瀻閻╊喖缍嶉妴鍌濆壖閺堫剛骞囬崷銊╃帛鐠併倛顕伴崣鏍ь樋娑擃亞顏崣锝囨窗瑜版洖鑻熼獮鎯邦攽濞村鈧噦绱濋張鈧崥搴℃値楠炶埖鍨氭稉鈧稉?CSV閵?
- Windows 姒涙顓婚敍姝?Ports "443,2053,2083,2087,2096,8443"`
- Linux 姒涙顓婚敍姝歅ORTS="443,2053,2083,2087,2096,8443"`
- 閸楁洜顏崣锝堫洬閻╂牭绱癢indows 閻?`-Port 8443`閿涘inux 閻?`PORT=8443`
- `443` 娑撳秶绮?`cfst` 娴?`-tp`閿涘奔濞囬悽?cfst 姒涙顓?443
- 闂?443 缁旑垰褰涙导姘辩舶 `cfst` 娴?`-tp <缁旑垰褰?`

婵″倹鐏夊ù瀣偓?`80` 缁旑垰褰涢敍瀹峜fst` 鏉╂﹢娓剁憰?HTTP 娑撳娴囧ù瀣偓鐔锋勾閸р偓閿?
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -Port 80 -DownloadTestUrl "http://speed.cloudflare.com/__down?bytes=99999999"
```

```bash
FORCE=1 PORT=80 DOWNLOAD_TEST_URL="http://speed.cloudflare.com/__down?bytes=99999999" ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

閸撳秵褰侀弰顖欑瑓鏉炵晫娈?`ip.zip` 闁插苯鐡ㄩ崷?`80` 閻╊喖缍嶉妴?
## GitHub Token

Windows閿?
```powershell
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN_CFOPT", "娴ｇ姷娈?token", "User")
```

Linux閿?
```bash
export GITHUB_TOKEN_CFOPT="娴ｇ姷娈?token"
```

## 娑擃參妫块弬鍥︽

- `CloudflareSpeedTest.csv`閿涙碍娓剁紒鍫濇値楠炴儼绻冨銈呮倵閸戝棗顦稉濠佺炊閻?CSV
- `CloudflareSpeedTest-443.csv`閿涙艾宕熸稉顏嗩伂閸欙絿娈戦崢鐔奉潗濞村鈧?CSV
- `selected-ip-443.txt`閿涙氨绮?`cfst` 娴ｈ法鏁ら惃鍕礋缁旑垰褰涙潏鎾冲弳
- `selected-ip-city-map-443.csv`閿涙艾宕熺粩顖氬經 IP 閸掓澘娴楃€?閸︽澘灏惃鍕Ё鐏?- `cfst-443-stdout.log` / `cfst-443-stderr.log`閿涙艾宕熺粩顖氬經濞村鈧喐妫╄箛?- `auto-push.log`閿涙碍鈧粯妫╄箛?- `last-success.txt`閿涙矮绗傚▎鈩冨灇閸旂喍绗傛导鐘虫闂?
## vps789 CT candidates

The scripts fetch `https://vps789.com/openApi/cfIpApi` by default and only use `data.CT`, which is the China Telecom Cloudflare preferred-IP list. These IPs are added to every CFST port input and tested together with candidates from `ip.zip`.

- Disabled by default because the CT API currently returns very few IPs
- Enable manually: Windows `-EnableVps789Ct`; Linux `ENABLE_VPS789_CT=1`
- Default limit: `Vps789CtLimit=100` / `VPS789_CT_LIMIT=50`
- Default filter: China Telecom latency `<=260ms`, China Telecom loss `<=5`
- Helper export: `VPS789_CF_CT_Candidates.csv`

`hostMonitorList` looks more like a VPS/domain/IP monitor list and is not guaranteed to contain only Cloudflare Anycast IPs, so it is not merged directly into the Edge Tunnel CSV. The main merged speed-test CSV only adds `cfIpApi.data.CT`, then lets CFST test and filter it.
