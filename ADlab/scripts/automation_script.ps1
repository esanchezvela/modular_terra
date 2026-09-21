#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory, Az.Accounts, Az.KeyVault

<#
.SYNOPSIS
    Prestages an Active Directory computer account with a cryptographically
    random initial password and stores the same password in Azure Key Vault.

.DESCRIPTION
    The script is idempotent and fail-safe.

    State handling:

      AD computer absent + Key Vault secret absent
          Creates both resources.

      AD computer present + Key Vault secret present
          Makes no changes and returns success.

      AD computer present + Key Vault secret absent
          Stops without changing the AD computer password.

      AD computer absent + Key Vault secret present
          Stops without overwriting or deleting the Key Vault secret.

    During new provisioning, the script creates the AD computer first and then
    writes the matching enrollment password to Key Vault. If the Key Vault write
    fails, it attempts to remove the newly created AD computer object so that a
    partial provisioning state is not intentionally retained.

    This script never displays or logs the enrollment password.

.EXAMPLE
    .\New-LinuxComputerEnrollment.ps1 `
        -ComputerName "LINUXVM01" `
        -ComputerOU "OU=LinuxServers,DC=contoso,DC=com" `
        -VaultName "kv-linux-domainjoin"

.EXAMPLE
    .\New-LinuxComputerEnrollment.ps1 `
        -ComputerName "LINUXVM01" `
        -ComputerOU "OU=LinuxServers,DC=contoso,DC=com" `
        -VaultName "kv-linux-domainjoin" `
        -SecretPrefix "ad-enrollment-" `
        -SubscriptionId "00000000-0000-0000-0000-000000000000" `
        -LogFile "C:\Logs\LINUXVM01-provisioning.log"
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[A-Za-z0-9-]{1,15}$")]
    [string]$ComputerName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerOU,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultName,

    [Parameter()]
    [ValidatePattern("^[A-Za-z0-9-]*$")]
    [string]$SecretPrefix = "",

    [Parameter()]
    [ValidateRange(32, 128)]
    [int]$PasswordLength = 64,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogFile = "C:\Logs\Linux-Computer-Provisioning.log"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$AzureConnected = $false
$ComputerCreatedByThisRun = $false
$EnrollmentPasswordPlainText = $null
$EnrollmentPassword = $null
$KeyVaultSecret = $null

#
# Normalize identifiers.
#
$NormalizedComputerName = $ComputerName.ToUpperInvariant()
$ComputerSamAccountName = "$NormalizedComputerName`$"
$SecretName = "$SecretPrefix$NormalizedComputerName"

#
# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
#

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "{0} [{1}] {2}" -f $Timestamp, $Level, $Message

    try {
        Add-Content `
            -LiteralPath $script:LogFile `
            -Value $Entry `
            -Encoding UTF8 `
            -ErrorAction Stop
    }
    catch {
        Write-Warning (
            "Unable to write to log file '{0}': {1}" -f
            $script:LogFile,
            $_.Exception.Message
        )
    }

    switch ($Level) {
        "INFO" {
            Write-Host $Entry
        }

        "WARNING" {
            Write-Host $Entry -ForegroundColor Yellow
        }

        "ERROR" {
            Write-Host $Entry -ForegroundColor Red
        }
    }
}

#
# ---------------------------------------------------------------------------
# HTTP error inspection
# ---------------------------------------------------------------------------
#

function ConvertTo-HttpStatusCode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $Value
    )

    try {
        return [int]$Value
    }
    catch {
        if (
            $null -ne $Value -and
            $Value.PSObject.Properties.Name -contains "value__"
        ) {
            try {
                return [int]$Value.value__
            }
            catch {
                return $null
            }
        }
    }

    return $null
}

function Get-ExceptionHttpStatusCode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $CurrentException = $Exception

    while ($null -ne $CurrentException) {
        if (
            $CurrentException.PSObject.Properties.Name -contains "StatusCode" -and
            $null -ne $CurrentException.StatusCode
        ) {
            $Code = ConvertTo-HttpStatusCode `
                -Value $CurrentException.StatusCode

            if ($null -ne $Code) {
                return $Code
            }
        }

        if (
            $CurrentException.PSObject.Properties.Name -contains "Response" -and
            $null -ne $CurrentException.Response -and
            $CurrentException.Response.PSObject.Properties.Name -contains "StatusCode"
        ) {
            $Code = ConvertTo-HttpStatusCode `
                -Value $CurrentException.Response.StatusCode

            if ($null -ne $Code) {
                return $Code
            }
        }

        $CurrentException = $CurrentException.InnerException
    }

    $ExceptionText = $Exception.ToString()

    if (
        $ExceptionText -match "(?i)\b401\b" -or
        $ExceptionText -match "(?i)\bUnauthorized\b"
    ) {
        return 401
    }

    if (
        $ExceptionText -match "(?i)\b403\b" -or
        $ExceptionText -match "(?i)\bForbidden\b" -or
        $ExceptionText -match "(?i)\bAccessDenied\b"
    ) {
        return 403
    }

    if (
        $ExceptionText -match "(?i)\b404\b" -or
        $ExceptionText -match "(?i)\bSecretNotFound\b" -or
        $ExceptionText -match "(?i)\bnot found\b"
    ) {
        return 404
    }

    return $null
}

#
# ---------------------------------------------------------------------------
# Cryptographically secure random-number helper
# ---------------------------------------------------------------------------
#

function Get-CryptoRandomInt {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int]$MaximumExclusive
    )

    $Bytes = New-Object byte[] 4

    $Limit = :MaxValue -
        (:MaxValue % [uint64]$MaximumExclusive)

    do {
        $script:RandomNumberGenerator.GetBytes($Bytes)

        $Value = :ToUInt32($Bytes, 0)
    }
    while ([uint64]$Value -ge $Limit)

    return [uint64]$Value % [uint64]$MaximumExclusive
}

#
# ---------------------------------------------------------------------------
# Generate an AD-compatible random enrollment password
# ---------------------------------------------------------------------------
#

function New-EnrollmentPassword {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateRange(32, 128)]
        [int]$Length
    )

    $Uppercase = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $Lowercase = "abcdefghijkmnopqrstuvwxyz"
    $Numbers   = "23456789"
    $Special   = "!#%+,-.:=@_"
    $All       = $Uppercase + $Lowercase + $Numbers + $Special

    $Characters = New-Object System.Collections.Generic.List[char]

    #
    # Guarantee inclusion of each character class.
    #
    $Characters.Add(
        $Uppercase[
            (Get-CryptoRandomInt -MaximumExclusive $Uppercase.Length)
        ]
    )

    $Characters.Add(
        $Lowercase[
            (Get-CryptoRandomInt -MaximumExclusive $Lowercase.Length)
        ]
    )

    $Characters.Add(
        $Numbers[
            (Get-CryptoRandomInt -MaximumExclusive $Numbers.Length)
        ]
    )

    $Characters.Add(
        $Special[
            (Get-CryptoRandomInt -MaximumExclusive $Special.Length)
        ]
    )

    while ($Characters.Count -lt $Length) {
        $Characters.Add(
            $All[
                (Get-CryptoRandomInt -MaximumExclusive $All.Length)
            ]
        )
    }

    #
    # Cryptographically shuffle the complete character set.
    #
    for ($Index = $Characters.Count - 1; $Index -gt 0; $Index--) {
        $SwapIndex = Get-CryptoRandomInt `
            -MaximumExclusive ($Index + 1)

        $TemporaryCharacter = $Characters[$Index]
        $Characters[$Index] = $Characters[$SwapIndex]
        $Characters[$SwapIndex] = $TemporaryCharacter
    }

    return -join $Characters
}

#
# ---------------------------------------------------------------------------
# Prepare logging
# ---------------------------------------------------------------------------
#

$LogDirectory = Split-Path -Path $LogFile -Parent

if (
    -not :IsNullOrWhiteSpace($LogDirectory) -and
    -not (Test-Path -LiteralPath $LogDirectory)
) {
    New-Item `
        -ItemType Directory `
        -Path $LogDirectory `
        -Force `
        -ErrorAction Stop | Out-Null
}

Write-Log "Starting Linux computer-account enrollment provisioning."
Write-Log "Computer name: $NormalizedComputerName"
Write-Log "Computer sAMAccountName: $ComputerSamAccountName"
Write-Log "Target OU: $ComputerOU"
Write-Log "Key Vault: $VaultName"
Write-Log "Key Vault secret name: $SecretName"

try {
    #
    # -----------------------------------------------------------------------
    # Load modules
    # -----------------------------------------------------------------------
    #

    Write-Log "Importing required PowerShell modules."

    Import-Module ActiveDirectory -ErrorAction Stop
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.KeyVault -ErrorAction Stop

    #
    # -----------------------------------------------------------------------
    # Validate the target OU
    # -----------------------------------------------------------------------
    #

    Write-Log "Validating target organizational unit."

    $TargetOU = Get-ADOrganizationalUnit `
        -Identity $ComputerOU `
        -ErrorAction Stop

    if ($null -eq $TargetOU) {
        throw "The target OU could not be found: $ComputerOU"
    }

    Write-Log "Target organizational unit validated."

    #
    # -----------------------------------------------------------------------
    # Authenticate using the provisioning VM's managed identity
    # -----------------------------------------------------------------------
    #

    Write-Log "Authenticating to Azure using the VM managed identity."

    Disable-AzContextAutosave `
        -Scope Process `
        -ErrorAction Stop | Out-Null

    Connect-AzAccount `
        -Identity `
        -ErrorAction Stop | Out-Null

    $AzureConnected = $true

    if (-not :IsNullOrWhiteSpace($SubscriptionId)) {
        Set-AzContext `
            -SubscriptionId $SubscriptionId `
            -ErrorAction Stop | Out-Null
    }

    Write-Log "Managed-identity authentication completed."

    #
    # -----------------------------------------------------------------------
    # Preflight: check the AD computer object
    # -----------------------------------------------------------------------
    #

    Write-Log "Checking Active Directory for the computer account."

    $EscapedSamAccountName =
        $ComputerSamAccountName.Replace("'", "''")

    $ExistingComputers = @(
        Get-ADComputer `
            -Filter "SamAccountName -eq '$EscapedSamAccountName'" `
            -Properties DistinguishedName, Enabled `
            -ErrorAction Stop
    )

    if ($ExistingComputers.Count -gt 1) {
        throw (
            "Multiple Active Directory computer objects were returned for " +
            "sAMAccountName '$ComputerSamAccountName'."
        )
    }

    $ExistingComputer =
        $ExistingComputers |
        Select-Object -First 1

    #
    # -----------------------------------------------------------------------
    # Preflight: check the Key Vault secret
    # -----------------------------------------------------------------------
    #

    Write-Log "Checking Azure Key Vault for the enrollment secret."

    $ExistingSecret = $null

    try {
        $ExistingSecret = Get-AzKeyVaultSecret `
            -VaultName $VaultName `
            -Name $SecretName `
            -ErrorAction Stop
    }
    catch {
        $StatusCode = Get-ExceptionHttpStatusCode `
            -Exception $_.Exception

        switch ($StatusCode) {
            401 {
                throw (
                    "Azure Key Vault returned HTTP 401 Unauthorized while " +
                    "checking secret '$SecretName'."
                )
            }

            403 {
                throw (
                    "Azure Key Vault returned HTTP 403 Forbidden while " +
                    "checking secret '$SecretName'. Verify managed-identity " +
                    "permissions and Key Vault network controls."
                )
            }

            404 {
                #
                # Expected state for a computer that has not been provisioned.
                #
                $ExistingSecret = $null
            }

            default {
                throw (
                    "Unable to determine whether Key Vault secret " +
                    "'$SecretName' exists: $($_.Exception.Message)"
                )
            }
        }
    }

    #
    # -----------------------------------------------------------------------
    # Evaluate existing state
    # -----------------------------------------------------------------------
    #

    $ComputerExists = $null -ne $ExistingComputer
    $SecretExists = $null -ne $ExistingSecret

    if ($ComputerExists -and $SecretExists) {
        Write-Log (
            "The AD computer account and Key Vault secret both already " +
            "exist. No changes are required."
        ) -Level "WARNING"

        Write-Host ""
        Write-Host "Provisioning state: Already provisioned"
        Write-Host "Computer:           $NormalizedComputerName"
        Write-Host "AD object:          $($ExistingComputer.DistinguishedName)"
        Write-Host "Key Vault:          $VaultName"
        Write-Host "Secret:             $SecretName"
        Write-Host "Action:             No changes"
        Write-Host ""

        return
    }

    if ($ComputerExists -and -not $SecretExists) {
        throw (
            "Fail-safe stop: AD computer '$ComputerSamAccountName' exists, " +
            "but Key Vault secret '$SecretName' does not exist. The script " +
            "will not reset the computer password automatically because that " +
            "could invalidate an existing machine credential."
        )
    }

    if (-not $ComputerExists -and $SecretExists) {
        throw (
            "Fail-safe stop: Key Vault secret '$SecretName' exists, but AD " +
            "computer '$ComputerSamAccountName' does not exist. The script " +
            "will not overwrite or reuse the existing secret automatically."
        )
    }

    #
    # -----------------------------------------------------------------------
    # Both resources are absent: begin new provisioning transaction
    # -----------------------------------------------------------------------
    #

    if (
        -not $PSCmdlet.ShouldProcess(
            "$NormalizedComputerName and Key Vault secret $SecretName",
            "Create AD computer account and enrollment secret"
        )
    ) {
        Write-Log "Provisioning was not approved or was executed with WhatIf." `
            -Level "WARNING"

        return
    }

    Write-Log "Generating a cryptographically random enrollment password."

    $RandomNumberGenerator =
        [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $EnrollmentPasswordPlainText =
            New-EnrollmentPassword -Length $PasswordLength
    }
    finally {
        $RandomNumberGenerator.Dispose()
        $RandomNumberGenerator = $null
    }

    $EnrollmentPassword = ConvertTo-SecureString `
        -String $EnrollmentPasswordPlainText `
        -AsPlainText `
        -Force

    #
    # -----------------------------------------------------------------------
    # Create the AD computer object
    # -----------------------------------------------------------------------
    #

    Write-Log "Creating Active Directory computer '$ComputerSamAccountName'."

    $CreatedComputer = New-ADComputer `
        -Name $NormalizedComputerName `
        -SamAccountName $ComputerSamAccountName `
        -AccountPassword $EnrollmentPassword `
        -Path $ComputerOU `
        -Enabled $true `
        -Description "Prestaged Linux computer enrollment account" `
        -PassThru `
        -ErrorAction Stop

    $ComputerCreatedByThisRun = $true

    Write-Log (
        "Active Directory computer created: " +
        $CreatedComputer.DistinguishedName
    )

    #
    # -----------------------------------------------------------------------
    # Verify the AD object before writing the secret
    # -----------------------------------------------------------------------
    #

    $VerifiedComputer = Get-ADComputer `
        -Identity $CreatedComputer.DistinguishedName `
        -Properties Enabled, SamAccountName `
        -ErrorAction Stop

    if ($null -eq $VerifiedComputer) {
        throw "The new AD computer object could not be verified."
    }

    if ($VerifiedComputer.SamAccountName -ne $ComputerSamAccountName) {
        throw (
            "The new AD computer object has an unexpected sAMAccountName. " +
            "Expected '$ComputerSamAccountName'; received " +
            "'$($VerifiedComputer.SamAccountName)'."
        )
    }

    if (-not $VerifiedComputer.Enabled) {
        throw "The new AD computer object is not enabled."
    }

    Write-Log "Active Directory computer creation verified."

    #
    # -----------------------------------------------------------------------
    # Recheck Key Vault immediately before writing
    #
    # This reduces the chance of overwriting a secret created concurrently
    # after the initial preflight check.
    # -----------------------------------------------------------------------
    #

    Write-Log "Performing final Key Vault conflict check."

    $ConcurrentSecret = $null

    try {
        $ConcurrentSecret = Get-AzKeyVaultSecret `
            -VaultName $VaultName `
            -Name $SecretName `
            -ErrorAction Stop
    }
    catch {
        $StatusCode = Get-ExceptionHttpStatusCode `
            -Exception $_.Exception

        if ($StatusCode -ne 404) {
            throw
        }
    }

    if ($null -ne $ConcurrentSecret) {
        throw (
            "A Key Vault secret named '$SecretName' appeared after the " +
            "preflight check. The script will not overwrite it."
        )
    }

    #
    # -----------------------------------------------------------------------
    # Store the exact same password in Azure Key Vault
    # -----------------------------------------------------------------------
    #

    Write-Log "Writing the enrollment secret to Azure Key Vault."

    $SecretTags = @{
        "ComputerName"      = $NormalizedComputerName
        "SamAccountName"    = $ComputerSamAccountName
        "ComputerObjectDN"  = $CreatedComputer.DistinguishedName
        "Purpose"           = "Linux-AD-Enrollment"
        "ProvisioningState" = "Pending-Consumption"
    }

    $KeyVaultSecret = Set-AzKeyVaultSecret `
        -VaultName $VaultName `
        -Name $SecretName `
        -SecretValue $EnrollmentPassword `
        -ContentType "Linux Active Directory enrollment password" `
        -Tag $SecretTags `
        -ErrorAction Stop

    if (
        $null -eq $KeyVaultSecret -or
        :IsNullOrWhiteSpace($KeyVaultSecret.Id)
    ) {
        throw (
            "Set-AzKeyVaultSecret returned without a verifiable secret ID."
        )
    }

    Write-Log (
        "Key Vault enrollment secret created successfully. " +
        "Secret version: $($KeyVaultSecret.Version)"
    )

    #
    # -----------------------------------------------------------------------
    # Final paired-state verification
    # -----------------------------------------------------------------------
    #

    Write-Log "Verifying the final paired provisioning state."

    $FinalComputer = Get-ADComputer `
        -Identity $CreatedComputer.DistinguishedName `
        -Properties Enabled, SamAccountName `
        -ErrorAction Stop

    $FinalSecret = Get-AzKeyVaultSecret `
        -VaultName $VaultName `
        -Name $SecretName `
        -ErrorAction Stop

    if ($null -eq $FinalComputer) {
        throw "Final verification could not retrieve the AD computer object."
    }

    if ($null -eq $FinalSecret) {
        throw "Final verification could not retrieve the Key Vault secret."
    }

    #
    # Provisioning is now committed. Do not roll back the AD object.
    #
    $ComputerCreatedByThisRun = $false

    Write-Log "Paired provisioning completed successfully."

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Linux Computer Enrollment Provisioning"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host "Computer:       $NormalizedComputerName"
    Write-Host "sAMAccountName: $ComputerSamAccountName"
    Write-Host "AD object:      $($FinalComputer.DistinguishedName)"
    Write-Host "Key Vault:      $VaultName"
    Write-Host "Secret name:    $SecretName"
    Write-Host "Secret version: $($FinalSecret.Version)"
    Write-Host "State:          Provisioned"
    Write-Host "Log:            $LogFile"
    Write-Host ""
}
catch {
    $OriginalError = $_.Exception

    Write-Log `
        "Provisioning failed: $($OriginalError.Message)" `
        -Level "ERROR"

    #
    # -----------------------------------------------------------------------
    # Roll back only an AD computer created by this execution.
    #
    # Never remove a computer object that existed before the script started.
    # -----------------------------------------------------------------------
    #

    if ($ComputerCreatedByThisRun) {
        Write-Log (
            "Attempting rollback of the newly created AD computer object."
        ) -Level "WARNING"

        try {
            $RollbackComputer = Get-ADComputer `
                -Identity $ComputerSamAccountName `
                -ErrorAction Stop

            Remove-ADComputer `
                -Identity $RollbackComputer `
                -Confirm:$false `
                -ErrorAction Stop

            Write-Log (
                "Rollback succeeded. The newly created AD computer object " +
                "was removed."
            ) -Level "WARNING"
        }
        catch {
            Write-Log (
                "CRITICAL: rollback failed. The AD computer object may exist " +
                "without a matching Key Vault secret. Rollback error: " +
                $_.Exception.Message
            ) -Level "ERROR"

            throw (
                "Provisioning failed and automatic rollback also failed. " +
                "Inspect AD computer '$ComputerSamAccountName', Key Vault " +
                "secret '$SecretName', and log '$LogFile'. Original error: " +
                $OriginalError.Message
            )
        }
    }

    throw $OriginalError
}
finally {
    #
    # Release references to secret material.
    #
    $EnrollmentPasswordPlainText = $null
    $EnrollmentPassword = $null
    $KeyVaultSecret = $null

    if ($AzureConnected) {
        Disconnect-AzAccount `
            -Scope Process `
            -ErrorAction SilentlyContinue | Out-Null

        Clear-AzContext `
            -Scope Process `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Write-Log "Script execution ended."
}
