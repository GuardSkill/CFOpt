param(
    [string]$InterfaceAlias = 'vEthernet (HA External)',
    [string]$DirectGateway = '192.168.0.1',
    [string]$DirectDnsServer = '192.168.0.1'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell window (Run as administrator).'
}

$adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop
if ($adapter.Status -ne 'Up') {
    throw "Network adapter '$InterfaceAlias' is not up."
}
if (-not (Test-Connection -ComputerName $DirectGateway -Count 1 -Quiet)) {
    throw "Direct gateway $DirectGateway is not reachable through the local network."
}

# These two routes are more specific than a DHCP-provided default route. They
# keep LAN routes intact while ensuring every public IPv4 destination bypasses
# the OpenClash side router. route.exe -p is used because some Windows builds
# reject New-NetRoute -PolicyStore PersistentStore with system error 87.
$splitRoutes = @(
    [pscustomobject]@{ Prefix = '0.0.0.0/1'; Network = '0.0.0.0' },
    [pscustomobject]@{ Prefix = '128.0.0.0/1'; Network = '128.0.0.0' }
)
foreach ($route in $splitRoutes) {
    $matching = @(
        Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $route.Prefix -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.NextHop -eq $DirectGateway }
    )
    if ($matching.Count -eq 0) {
        & route.exe -p ADD $route.Network MASK 128.0.0.0 $DirectGateway METRIC 1 IF $adapter.ifIndex | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "route.exe failed to add $($route.Prefix) through $DirectGateway (exit $LASTEXITCODE)."
        }
    }
}

Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($DirectDnsServer)
Clear-DnsClientCache

$routes = @(
    Get-NetRoute -AddressFamily IPv4 -InterfaceIndex $adapter.ifIndex |
        Where-Object { $_.DestinationPrefix -in @('0.0.0.0/1', '128.0.0.0/1') -and $_.NextHop -eq $DirectGateway }
)
if (@($routes.DestinationPrefix | Select-Object -Unique).Count -ne 2) {
    throw 'The direct split routes were not installed completely.'
}

$dnsAnswers = @(
    Resolve-DnsName -Name 'api.ip.sb' -Type A -DnsOnly -ErrorAction Stop |
        Where-Object IPAddress |
        ForEach-Object IPAddress
)
if (@($dnsAnswers | Where-Object { $_ -match '^198\.(18|19)\.' }).Count -gt 0) {
    throw "DNS still returns an OpenClash Fake-IP address: $($dnsAnswers -join ', ')"
}

Write-Host "CFOpt direct network configured on '$InterfaceAlias'."
Write-Host "Internet route: $DirectGateway; DNS: $DirectDnsServer"
Write-Host "api.ip.sb resolves to: $($dnsAnswers -join ', ')"
