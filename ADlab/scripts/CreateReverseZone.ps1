#Requires -RunAsAdministrator
#Requires -Modules DnsServer

$ErrorActionPreference = "Stop"

$defaultRoute = Get-NetRoute `
    -AddressFamily IPv4 `
    -DestinationPrefix "0.0.0.0/0" |
    Sort-Object RouteMetric, InterfaceMetric |
    Select-Object -First 1

if (-not $defaultRoute) {
    throw "No IPv4 default route was found."
}

$addresses = @(
    Get-NetIPAddress `
        -AddressFamily IPv4 `
        -InterfaceIndex $defaultRoute.InterfaceIndex |
    Where-Object {
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.254.*" -and
        -not $_.SkipAsSource
    }
)

if ($addresses.Count -ne 1) {
    throw "Expected one eligible IPv4 address on the primary interface; found $($addresses.Count)."
}

$ipAddress = $addresses[0].IPAddress
$octets = $ipAddress.Split(".")

$fqdn = (
    [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
).TrimEnd(".").ToLowerInvariant()

if (-not $fqdn.Contains(".")) {
    throw "Unable to determine the domain controller FQDN: $fqdn"
}

$networkId = "{0}.{1}.{2}.0/24" -f `
    $octets[0], $octets[1], $octets[2]

$reverseZoneName = "{0}.{1}.{2}.in-addr.arpa" -f `
    $octets[2], $octets[1], $octets[0]

$recordName = $octets[3]
$ptrTarget = "$fqdn."

Write-Host "IPv4 address: $ipAddress"
Write-Host "Reverse network: $networkId"
Write-Host "Reverse zone: $reverseZoneName"
Write-Host "PTR target: $ptrTarget"

$zone = Get-DnsServerZone `
    -Name $reverseZoneName `
    -ErrorAction SilentlyContinue

if (-not $zone) {
    Add-DnsServerPrimaryZone `
        -NetworkId $networkId `
        -ReplicationScope Domain `
        -DynamicUpdate Secure

    Write-Host "Created reverse zone $reverseZoneName"
}

$existingRecords = @(
    Get-DnsServerResourceRecord `
        -ZoneName $reverseZoneName `
        -Name $recordName `
        -RRType PTR `
        -ErrorAction SilentlyContinue
)

$correctRecord = $existingRecords | Where-Object {
    $_.RecordData.PtrDomainName.ToString().TrimEnd(".") -ieq $fqdn
}

if ($correctRecord -and $existingRecords.Count -eq 1) {
    Write-Host "PTR record already exists: $ipAddress -> $fqdn"
} else {
    foreach ($record in $existingRecords) {
        Remove-DnsServerResourceRecord `
            -ZoneName $reverseZoneName `
            -InputObject $record `
            -Force
    }

    Add-DnsServerResourceRecordPtr `
        -ZoneName $reverseZoneName `
        -Name $recordName `
        -PtrDomainName $ptrTarget

    Write-Host "Created PTR record: $ipAddress -> $fqdn"
}

Resolve-DnsName $ipAddress -Type PTR
