# CFOpt Auto Push

This package automates your workflow:

1. Download `https://zip.cm.edu.kg/ip.zip`
2. Extract country IP files
3. Merge `HK, KR, SG, PH, VN, MY, KZ, MN, IE, US`
4. Run `H:\PyProjects\cfst_windows_amd64\cfst.exe` with cfst's default port 443
5. Generate `H:\PyProjects\CFOptAutoPush\CloudflareSpeedTest.csv`
6. Push it to `GuardSkill/CFOpt/main/CloudflareSpeedTest.csv`
7. Run automatically at Windows startup, but only once every 6 days after the last successful upload

## Files

- `Invoke-CFOptAutoPush.ps1`: main pipeline
- `Install-CFOptAutoPushTask.ps1`: scheduled task installer
- `README-CFOptAutoPush.md`: this guide

## 1. Create a GitHub token

Create a GitHub fine-grained personal access token with write access to the `GuardSkill/CFOpt` repository contents.

Then set it as a user environment variable:

```powershell
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN_CFOPT", "paste_your_token_here", "User")
```

Close and reopen PowerShell after setting the token.

## 2. Test without upload

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\GuardSkill\Documents\Codex\2026-06-27\ni\outputs\Invoke-CFOptAutoPush.ps1" -DryRun
```

This downloads and extracts the zip, merges the selected country IP files, and prints the `cfst` command it would run.

## Port behavior

The script intentionally does not pass `-tp`, so `cfst` uses its official default port: `443`.

The zip source contains folders named by port. The script reads only the folder matching `-Port`, so `-Port 443` reads the `443` folder, and `-Port 8443` reads the `8443` folder and calls `cfst -tp 8443`.

Only use a non-default port when you also set the matching `cfst` options. For example, port 80 needs an HTTP download URL:

```powershell
cfst -tp 80 -url http://speed.cloudflare.com/__down?bytes=99999999
```

Equivalent script usage:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\GuardSkill\Documents\Codex\2026-06-27\ni\outputs\Invoke-CFOptAutoPush.ps1" -Force -Port 80 -DownloadTestUrl "http://speed.cloudflare.com/__down?bytes=99999999"
```

That only works if the downloaded zip contains an `80` folder. If the port folder is missing, the script stops instead of mixing IP files from another port.

## 3. Run once now

To generate the CSV without uploading to GitHub:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\GuardSkill\Documents\Codex\2026-06-27\ni\outputs\Invoke-CFOptAutoPush.ps1" -Force -SkipUpload
```

To generate and upload:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\GuardSkill\Documents\Codex\2026-06-27\ni\outputs\Invoke-CFOptAutoPush.ps1" -Force
```

Use `-Force` to ignore the 6-day interval for a manual run.

## 4. Install startup automation

Run PowerShell as administrator, then execute:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\GuardSkill\Documents\Codex\2026-06-27\ni\outputs\Install-CFOptAutoPushTask.ps1"
```

The task name is `CFOpt Auto Push`.

## Logs and generated files

The working directory is:

```text
H:\PyProjects\CFOptAutoPush
```

Important files:

- `auto-push.log`: run log
- `last-success.txt`: last successful GitHub upload time
- `ip.zip`: downloaded zip
- `ip.download.zip`: temporary download file, removed automatically
- `extract`: extracted zip contents
- `selected-ip.txt`: merged country IP input
- `CloudflareSpeedTest.csv`: generated CSV
- `cfst-stdin.txt`: contains a blank line so the automation can satisfy cfst's final "press Enter" prompt
- `cfst-stdout.log` / `cfst-stderr.log`: captured cfst output from the latest run

## Common issues

- Missing token: set `GITHUB_TOKEN_CFOPT`.
- Missing `cfst.exe`: confirm `H:\PyProjects\cfst_windows_amd64\cfst.exe` exists.
- Download blocked: the source sometimes returns a Cloudflare challenge. If `ip.zip` already exists, the script logs a warning and uses the cached zip.
- Country file not found: the script logs a warning and continues with available countries. If every requested country is missing, the run stops.
- GitHub metadata returns 404: the script treats this as "target CSV does not exist yet" and creates it. If upload still returns 404, check that the repository name, branch, token permissions, and private repository access are correct.
- GitHub upload fails: confirm the token has repository contents write permission.
- Scheduled task does not run: reinstall from an administrator PowerShell window.
