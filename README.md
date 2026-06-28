# CFOpt 鑷姩娴嬮€熶笌鎺ㄩ€?
杩欏鑴氭湰浼氳嚜鍔ㄤ笅杞?`ip.zip`锛屾寜澶氫釜绔彛骞惰娴嬮€燂紝鍚堝苟缁撴灉锛岃繃婊や笉鍙敤鎴栭珮寤惰繜鑺傜偣锛岀劧鍚庢妸鏈€缁?CSV 涓婁紶鍒?`GuardSkill/CFOpt`銆?
## 涓婁紶鏂囦欢

- Windows/CD 榛樿涓婁紶锛歚CloudflareSpeedTest_CD.csv`
- Linux/BJ 榛樿涓婁紶锛歚CloudflareSpeedTest_BJ.csv`
- 璁㈤槄杞崲閰嶇疆锛歚CFOpt_Subconverter.ini`

## 鏁版嵁娴佺▼

1. 涓嬭浇 `https://zip.cm.edu.kg/ip.zip`
2. 瑙ｅ帇骞惰鍙栧涓鍙ｇ洰褰曪紝榛樿 `443`銆乣2053`銆乣2083`銆乣2087`銆乣2096`銆乣8443`
3. 姣忎釜绔彛鍒嗗埆鍚堝苟鎸囧畾鍥藉/鍦板尯鏂囦欢锛屼緥濡?`HK.txt`銆乣KR.txt`銆乣SG.txt`
4. 姣忎釜绔彛鐢熸垚鐙珛鐨?IP 鍒板浗瀹?鍦板尯鏄犲皠锛屼緥濡?`selected-ip-city-map-443.csv`
5. 姣忎釜绔彛鍚姩涓€涓?`cfst` 杩涚▼锛屽苟琛屾祴閫?6. 鍚堝苟鎵€鏈夌鍙ｇ殑 CSV 缁撴灉
7. 杩囨护涓嶅彲鐢ㄦ垨楂樺欢杩熺粨鏋?8. 姣忎釜鍥藉/鍦板尯鏈€澶氫繚鐣?Top 20锛屼紭鍏堜笅杞介€熷害鏇撮珮锛屽叾娆″钩鍧囧欢杩熸洿浣?9. 杈撳嚭 edgetunnel 鍏煎鍒楋細`IP鍦板潃`銆乣绔彛`銆乣鏁版嵁涓績`銆乣鍩庡競`銆乣TLS`
10. 涓婁紶鍒?GitHub

鏈€缁堣妭鐐瑰娉ㄤ細绫讳技锛?
```text
198.41.223.63:2096#SG [86ms 76.20Mbps]
```

## 榛樿杩囨护瑙勫垯

- 淇濈暀 `宸叉帴鏀?>= 1`
- 淇濈暀 `涓㈠寘鐜?< 1`
- 淇濈暀 `骞冲潎寤惰繜 <= 420`
- 淇濈暀 `涓嬭浇閫熷害 >= 0.01 Mbps`锛岄伩鍏?0.00 閫熺粨鏋滆繘鍏ヨ闃?- 姣忎釜鍥藉/鍦板尯鏈€澶氫繚鐣?`20` 鏉★紝璺ㄦ墍鏈夋祴璇曠鍙ｄ竴璧锋帓鍚?
涓存椂璋冩暣寤惰繜闃堝€硷細

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -MaxLatencyMs 300
```

```bash
FORCE=1 MAX_LATENCY_MS=300 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

濡傛灉缁撴灉鍏ㄦ槸 `0.00 MB/s`锛岀敤 cfst 璋冭瘯妯″紡鎺掓煡涓嬭浇娴嬮€熷湴鍧€銆両P 鎴栫綉缁滈棶棰橈細

```bash
FORCE=1 CFST_DEBUG=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CfstDebug
```

## Windows 浣跨敤

榛樿璺緞锛?
```text
H:\PyProjects\cfst_windows_amd64\cfst.exe
H:\PyProjects\CFOptAutoPush
```

鍙笅杞姐€佽В鍘嬨€佸噯澶囪緭鍏ワ紝涓嶆祴閫熴€佷笉涓婁紶锛?
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -DryRun
```

鐢熸垚 CSV 浣嗕笉涓婁紶锛?
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -SkipUpload
```

榛樿澶氱鍙ｅ苟琛屾祴閫熷苟涓婁紶锛?
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force
```

鎸囧畾涓€缁勭鍙ｏ細

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -Ports "443,2053,2083,2087,2096,8443"
```

涓存椂鍙祴鍗曠鍙ｏ細

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -Port 8443
```

## Linux 浣跨敤

涓€琛屽畨瑁呭苟绔嬪嵆杩愯锛?
```bash
GITHUB_TOKEN_CFOPT="浣犵殑 token" bash -c "$(curl -fsSL https://raw.githubusercontent.com/GuardSkill/CFOpt/main/scripts/linux/install-and-run-cfopt-linux.sh)"
```

濡傛灉宸茬粡鍦ㄤ粨搴撶洰褰曢噷锛屽彧鏄兂鎵嬪姩绔嬪嵆鏇存柊涓€娆★紝鐢細

```bash
FORCE=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

鍑嗗 `cfst`锛?
```bash
mkdir -p "$HOME/cfopt-auto-push"
cp ./cfst "$HOME/cfopt-auto-push/cfst"
chmod +x "$HOME/cfopt-auto-push/cfst"
chmod +x ./scripts/linux/invoke-cfopt-auto-push-linux.sh
export GITHUB_TOKEN_CFOPT="浣犵殑 token"
```

榛樿澶氱鍙ｅ苟琛屾祴閫熷苟涓婁紶锛?
```bash
FORCE=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

鐢熸垚 CSV 浣嗕笉涓婁紶锛?
```bash
FORCE=1 SKIP_UPLOAD=1 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

鎸囧畾绔彛鍒楄〃锛?
```bash
FORCE=1 PORTS="443,2053,2083,2087,2096,8443" ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

涓存椂鍙祴鍗曠鍙ｏ細

```bash
FORCE=1 PORT=8443 ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

甯哥敤鐜鍙橀噺锛?
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

## 绔彛璇存槑

`ip.zip` 閲岄潰宸茬粡鎸夌鍙ｅ垎鐩綍銆傝剼鏈幇鍦ㄩ粯璁よ鍙栧涓鍙ｇ洰褰曞苟骞惰娴嬮€燂紝鏈€鍚庡悎骞舵垚涓€涓?CSV銆?
- Windows 榛樿锛歚-Ports "443,2053,2083,2087,2096,8443"`
- Linux 榛樿锛歚PORTS="443,2053,2083,2087,2096,8443"`
- 鍗曠鍙ｈ鐩栵細Windows 鐢?`-Port 8443`锛孡inux 鐢?`PORT=8443`
- `443` 涓嶇粰 `cfst` 浼?`-tp`锛屼娇鐢?cfst 榛樿 443
- 闈?443 绔彛浼氱粰 `cfst` 浼?`-tp <绔彛>`

濡傛灉娴嬮€?`80` 绔彛锛宍cfst` 杩橀渶瑕?HTTP 涓嬭浇娴嬮€熷湴鍧€锛?
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -Port 80 -DownloadTestUrl "http://speed.cloudflare.com/__down?bytes=99999999"
```

```bash
FORCE=1 PORT=80 DOWNLOAD_TEST_URL="http://speed.cloudflare.com/__down?bytes=99999999" ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

鍓嶆彁鏄笅杞界殑 `ip.zip` 閲屽瓨鍦?`80` 鐩綍銆?
## GitHub Token

Windows锛?
```powershell
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN_CFOPT", "浣犵殑 token", "User")
```

Linux锛?
```bash
export GITHUB_TOKEN_CFOPT="浣犵殑 token"
```

## 涓棿鏂囦欢

- `CloudflareSpeedTest.csv`锛氭渶缁堝悎骞惰繃婊ゅ悗鍑嗗涓婁紶鐨?CSV
- `CloudflareSpeedTest-443.csv`锛氬崟涓鍙ｇ殑鍘熷娴嬮€?CSV
- `selected-ip-443.txt`锛氱粰 `cfst` 浣跨敤鐨勫崟绔彛杈撳叆
- `selected-ip-city-map-443.csv`锛氬崟绔彛 IP 鍒板浗瀹?鍦板尯鐨勬槧灏?- `cfst-443-stdout.log` / `cfst-443-stderr.log`锛氬崟绔彛娴嬮€熸棩蹇?- `auto-push.log`锛氭€绘棩蹇?- `last-success.txt`锛氫笂娆℃垚鍔熶笂浼犳椂闂?
## vps789 CT candidates

The scripts fetch `https://vps789.com/openApi/cfIpApi` by default and only use `data.CT`, which is the China Telecom Cloudflare preferred-IP list. These IPs are added to every CFST port input and tested together with candidates from `ip.zip`.

- Enabled by default: Windows enabled; Linux `ENABLE_VPS789_CT=1`
- Disable: Windows `-DisableVps789Ct`; Linux `ENABLE_VPS789_CT=0`
- Default limit: `Vps789CtLimit=50` / `VPS789_CT_LIMIT=50`
- Default filter: China Telecom latency `<=260ms`, China Telecom loss `<=5`
- Helper export: `VPS789_CF_CT_Candidates.csv`

`hostMonitorList` looks more like a VPS/domain/IP monitor list and is not guaranteed to contain only Cloudflare Anycast IPs, so it is not merged directly into the Edge Tunnel CSV. The main merged speed-test CSV only adds `cfIpApi.data.CT`, then lets CFST test and filter it.
