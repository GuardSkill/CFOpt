param([string]$OutputDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'dist'))
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework 4.x C# compiler is required.' }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$output = Join-Path $OutputDir 'CFOpt-Runner-Setup-SC.exe'
$source = Join-Path $PSScriptRoot 'installer\RunnerInstaller.cs'
$script = Join-Path $PSScriptRoot 'installer\Install-Runner.ps1'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ "/out:$output" `
    /reference:System.Windows.Forms.dll /reference:System.Drawing.dll `
    "/resource:$script,Install-Runner.ps1" $source
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Write-Output "Built: $output"
Get-FileHash -LiteralPath $output -Algorithm SHA256
