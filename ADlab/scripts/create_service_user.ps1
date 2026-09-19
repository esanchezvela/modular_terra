#Requires -Modules ActiveDirectory
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Creates a dedicated AD service account for prestaging Linux computer
    accounts and delegates Create Computer permissions on a specific OU.

.DESCRIPTION
    Intended architecture:

        svc-linux-prestage
                |
                | Create Computer Objects
                v
        OU=LinuxServers
                |
                +-- LINUXVM01$
                +-- LINUXVM02$
                +-- LINUXVM03$

    The account receives permissions ONLY on the specified OU.
#>


[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$ServiceAccountName,

    [Parameter(Mandatory)]
    [string]$ComputerOU
)

function Ensure-ADOUPath {
    param (
        [Parameter(Mandatory)]
        [string[]]$OUPath
    )

    $CurrentPath = (Get-ADDomain).DistinguishedName

    foreach ($OUName in $OUPath) {

        $ExistingOU = Get-ADOrganizationalUnit `
            -Filter "Name -eq '$OUName'" `
            -SearchBase $CurrentPath `
            -SearchScope OneLevel `
            -ErrorAction SilentlyContinue

        if (-not $ExistingOU) {
            $ExistingOU = New-ADOrganizationalUnit `
                -Name $OUName `
                -Path $CurrentPath `
                -PassThru
        }

        $CurrentPath = $ExistingOU.DistinguishedName
    }

    return $CurrentPath
}

$LinuxOU = Ensure-ADOUPath @(
    "Servers",
    "LinuxServers"
)



$ServiceAccountName  = "svc-linux-domainjoin"
$ErrorActionPreference = 'Stop'

Import-Module ActiveDirectory

Write-Host "Creating/preparing AD prestaging account: $ServiceAccountName" -ForegroundColor Cyan

#
# Determine domain information
#

$Domain = Get-ADDomain
$DomainDN = $Domain.DistinguishedName
$DnsRoot  = $Domain.DNSRoot

#
# Validate target OU
#

try {
    $OU = Get-ADOrganizationalUnit -Identity $ComputerOU
}
catch {
    throw "The specified OU does not exist: $ComputerOU"
}

Write-Host "Target OU: $($OU.DistinguishedName)"

#
# Create the service account if it doesn't exist
#

$ServiceAccount = Get-ADUser `
    -Filter "SamAccountName -eq '$ServiceAccountName'" `
    -ErrorAction SilentlyContinue

if (-not $ServiceAccount) {

    $Password = Read-Host `
        "Enter initial password for $ServiceAccountName" `
        -AsSecureString

    $ServiceAccount = New-ADUser `
        -Name $ServiceAccountName `
        -SamAccountName $ServiceAccountName `
        -UserPrincipalName "$ServiceAccountName@$DnsRoot" `
        -AccountPassword $Password `
        -Enabled $true `
        -PasswordNeverExpires $false `
        -CannotChangePassword $false `
        -PassThru

    Write-Host "Created service account." -ForegroundColor Green
}
else {
    Write-Host "Service account already exists." -ForegroundColor Yellow
}

#
# Get SID
#

$ServiceAccount = Get-ADUser `
    -Identity $ServiceAccountName `
    -Properties SID

$SID = $ServiceAccount.SID

Write-Host "Service account SID: $SID"

#
# Computer object schema GUID
#
# This GUID is obtained dynamically rather than hard-coded.
#

$RootDSE = Get-ADRootDSE

$ComputerSchema = Get-ADObject `
    -SearchBase $RootDSE.SchemaNamingContext `
    -LDAPFilter '(lDAPDisplayName=computer)' `
    -Properties schemaIDGUID

$ComputerObjectGuid = New-Object Guid (,$ComputerSchema.schemaIDGUID)

Write-Host "Computer object GUID: $ComputerObjectGuid"

#
# Load OU ACL
#

$OUPath = "AD:\$ComputerOU"
$ACL = Get-Acl $OUPath

$Identity = New-Object System.Security.Principal.SecurityIdentifier($SID)

#
# Grant:
#
#     Create Child -> Computer objects
#
# on this OU.
#

$CreateComputerRule = New-Object `
    System.DirectoryServices.ActiveDirectoryAccessRule(
        $Identity,
        [System.DirectoryServices.ActiveDirectoryRights]::CreateChild,
        [System.Security.AccessControl.AccessControlType]::Allow,
        $ComputerObjectGuid,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::None
    )

$ACL.AddAccessRule($CreateComputerRule)

#
# Write ACL
#

Set-Acl `
    -Path $OUPath `
    -AclObject $ACL

Write-Host ""
Write-Host "Delegation completed successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Account: $ServiceAccountName"
Write-Host "OU:      $ComputerOU"
Write-Host "Rights:  Create Computer Objects"
