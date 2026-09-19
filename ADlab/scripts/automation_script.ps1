#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory, Az.Accounts, Az.KeyVault

<#
.SYNOPSIS
    Creates or prepares an Active Directory service account for prestaging
    Linux computer objects and delegates Create Computer permissions on an OU.

.DESCRIPTION
    This script:

    1. Checks whether the Active Directory service account already exists.
    2. If the account does not exist:
       - Authenticates to Azure using the VM's system-assigned managed identity.
       - Retrieves the account password from Azure Key Vault.
       - Treats HTTP 401 and HTTP 403 responses as fatal.
       - Retries other Key Vault retrieval failures.
       - Enforces an overall polling timeout.
       - Creates the Active Directory service account.
    3. Retrieves the Computer object schema GUID.
    4. Adds an OU ACL allowing the service account to create Computer objects.
    5. Avoids adding an equivalent ACL entry more than once.
    6. Writes operational information to a log without recording secret values.

    The secret remains a SecureString and is passed directly to New-ADUser.

.EXAMPLE
    .\Create-LinuxPrestageAccount.ps1 `
        -ServiceAccountName "svc-linux-domainjoin" `
        -ComputerOU "OU=LinuxServers,DC=contoso,DC=com" `
        -VaultName "kv-linux-domainjoin" `
        -SecretName "svc-linux-domainjoin-password"

.EXAMPLE
    .\Create-LinuxPrestageAccount.ps1 `
        -ServiceAccountName "svc-linux-domainjoin" `
        -ComputerOU "OU=LinuxServers,DC=contoso,DC=com" `
        -VaultName "kv-linux-domainjoin" `
        -SecretName "svc-linux-domainjoin-password" `
        -SubscriptionId "00000000-0000-0000-0000-000000000000" `
        -MaxAttempts 10 `
        -RetryDelaySeconds 30 `
        -TimeoutSeconds 600 `
        -Verbose
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceAccountName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerOU,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SecretName,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$MaxAttempts = 10,

    [Parameter()]
    [ValidateRange(1, 3600)]
    [int]$RetryDelaySeconds = 30,

    [Parameter()]
    [ValidateRange(1, 86400)]
    [int]$TimeoutSeconds = 600,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogFile = "C:\Logs\Linux-AD-Prestage.log",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId
)

Set-StrictMode -Version 2.0

$ErrorActionPreference = "Stop"

$Secret = $null
$AccountPassword = $null
$AzureConnected = $false
$Stopwatch = $null

#
# ---------------------------------------------------------------------------
# Logging function
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
    $LogEntry = "{0} [{1}] {2}" -f $Timestamp, $Level, $Message

    try {
        Add-Content `
            -LiteralPath $script:LogFile `
            -Value $LogEntry `
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
            Write-Host $LogEntry
        }

        "WARNING" {
            Write-Host $LogEntry -ForegroundColor Yellow
        }

        "ERROR" {
            Write-Host $LogEntry -ForegroundColor Red
        }
    }
}

#
# ---------------------------------------------------------------------------
# Convert an HTTP status value to an integer
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
        try {
            if (
                $null -ne $Value -and
                $Value.PSObject.Properties.Name -contains "value__"
            ) {
                return [int]$Value.value__
            }
        }
        catch {
            return $null
        }
    }

    return $null
}

#
# ---------------------------------------------------------------------------
# Extract HTTP status code from an exception
# ---------------------------------------------------------------------------
#

function Get-ExceptionHttpStatusCode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $CurrentException = $Exception

    while ($null -ne $CurrentException) {
        #
        # Some Az exceptions expose StatusCode directly.
        #
        if (
            $CurrentException.PSObject.Properties.Name -contains "StatusCode" -and
            $null -ne $CurrentException.StatusCode
        ) {
            $StatusCode = ConvertTo-HttpStatusCode `
                -Value $CurrentException.StatusCode

            if ($null -ne $StatusCode) {
                return $StatusCode
            }
        }

        #
        # Other exceptions expose Response.StatusCode.
        #
        if (
            $CurrentException.PSObject.Properties.Name -contains "Response" -and
            $null -ne $CurrentException.Response
        ) {
            $Response = $CurrentException.Response

            if (
                $Response.PSObject.Properties.Name -contains "StatusCode" -and
                $null -ne $Response.StatusCode
            ) {
                $StatusCode = ConvertTo-HttpStatusCode `
                    -Value $Response.StatusCode

                if ($null -ne $StatusCode) {
                    return $StatusCode
                }
            }
        }

        $CurrentException = $CurrentException.InnerException
    }

    #
    # Compatibility fallback for module versions that only include
    # the HTTP status in the exception text.
    #
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

    return $null
}

#
# ---------------------------------------------------------------------------
# Create the log directory
# ---------------------------------------------------------------------------
#

$LogDirectory = Split-Path -Path $LogFile -Parent

if (
    -not [string]::Is -and
    -not (Test-Path -LiteralPath $LogDirectory)
) {
    try {
        New-Item `
            -ItemType Directory `
            -Path $LogDirectory `
            -Force `
            -ErrorAction Stop | Out-Null
    }
    catch {
        throw (
            "Unable to create log directory '{0}': {1}" -f
            $LogDirectory,
            $_.Exception.Message
        )
    }
}

Write-Log "Starting Linux Active Directory prestaging configuration."
Write-Log "Service account: $ServiceAccountName"
Write-Log "Target OU: $ComputerOU"

try {
    #
    # -----------------------------------------------------------------------
    # Import required modules
    # -----------------------------------------------------------------------
    #

    Write-Log "Importing required PowerShell modules."

    Import-Module ActiveDirectory -ErrorAction Stop
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.KeyVault -ErrorAction Stop

    Write-Log "Required PowerShell modules imported successfully."

    #
    # -----------------------------------------------------------------------
    # Determine Active Directory domain information
    # -----------------------------------------------------------------------
    #

    Write-Log "Retrieving Active Directory domain information."

    $Domain = Get-ADDomain -ErrorAction Stop

    $DomainDN = $Domain.DistinguishedName
    $DnsRoot = $Domain.DNSRoot

    if ([string]::Is {
        throw "Get-ADDomain did not return a distinguished name."
    }

    if ([string]::Is {
        throw "Get-ADDomain did not return a DNS root."
    }

    Write-Log "Active Directory domain detected: $DnsRoot"

    #
    # -----------------------------------------------------------------------
    # Validate target OU
    # -----------------------------------------------------------------------
    #

    Write-Log "Validating target OU."

    try {
        $OU = Get-ADOrganizationalUnit `
            -Identity $ComputerOU `
            -ErrorAction Stop
    }
    catch {
        throw (
            "The specified OU does not exist or cannot be accessed: {0}. {1}" -f
            $ComputerOU,
            $_.Exception.Message
        )
    }

    Write-Log "Target OU validated successfully."

    #
    # -----------------------------------------------------------------------
    # Check whether the service account already exists
    # -----------------------------------------------------------------------
    #

    Write-Log "Checking whether service account '$ServiceAccountName' exists."

    $EscapedServiceAccountName = $ServiceAccountName.Replace("'", "''")

    $ServiceAccounts = @(
        Get-ADUser `
            -Filter "SamAccountName -eq '$EscapedServiceAccountName'" `
            -ErrorAction Stop
    )

    if ($ServiceAccounts.Count -gt 1) {
        throw (
            "Multiple Active Directory users were returned for " +
            "sAMAccountName '$ServiceAccountName'."
        )
    }

    $ServiceAccount = $ServiceAccounts | Select-Object -First 1

    if ($null -ne $ServiceAccount) {
        Write-Log `
            "Service account already exists. Key Vault retrieval is not required." `
            -Level "WARNING"
    }
    else {
        Write-Log (
            "Service account does not exist. Retrieving its password " +
            "from Azure Key Vault."
        )

        #
        # -------------------------------------------------------------------
        # Authenticate using the VM system-assigned managed identity
        # -------------------------------------------------------------------
        #

        try {
            Write-Log (
                "Authenticating to Azure using the VM system-assigned " +
                "managed identity."
            )

            Disable-AzContextAutosave `
                -Scope Process `
                -ErrorAction Stop | Out-Null

            Connect-AzAccount `
                -Identity `
                -ErrorAction Stop | Out-Null

            $AzureConnected = $true

            if (-not [string]::Is {
                Write-Log "Selecting Azure subscription '$SubscriptionId'."

                Set-AzContext `
                    -SubscriptionId $SubscriptionId `
                    -ErrorAction Stop | Out-Null
            }

            Write-Log "Managed identity authentication completed successfully."
        }
        catch {
            $AuthenticationStatusCode = Get-ExceptionHttpStatusCode `
                -Exception $_.Exception

            switch ($AuthenticationStatusCode) {
                401 {
                    Write-Log `
                        "Fatal Azure authentication error: HTTP 401 Unauthorized." `
                        -Level "ERROR"

                    throw (
                        "Managed identity authentication failed with " +
                        "HTTP 401 Unauthorized."
                    )
                }

                403 {
                    Write-Log `
                        "Fatal Azure authorization error: HTTP 403 Forbidden." `
                        -Level "ERROR"

                    throw (
                        "Managed identity authentication failed with " +
                        "HTTP 403 Forbidden."
                    )
                }

                default {
                    Write-Log `
                        "Managed identity authentication failed: $($_.Exception.Message)" `
                        -Level "ERROR"

                    throw
                }
            }
        }

        #
        # -------------------------------------------------------------------
        # Retrieve Key Vault secret
        # -------------------------------------------------------------------
        #

        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $FatalKeyVaultError = $false
        $LastRetrievalError = $null
        $AttemptsPerformed = 0

        for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
            if ($Stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                Write-Log (
                    "Overall Key Vault polling timeout of $TimeoutSeconds " +
                    "seconds was reached before attempt $Attempt."
                ) -Level "ERROR"

                break
            }

            $AttemptsPerformed = $Attempt

            try {
                $ElapsedSeconds = :Round(
                    $Stopwatch.Elapsed.TotalSeconds,
                    2
                )

                Write-Log (
                    "Attempt $Attempt of $MaxAttempts retrieving secret " +
                    "'$SecretName' from vault '$VaultName'. " +
                    "Elapsed time: $ElapsedSeconds seconds."
                )

                $Secret = Get-AzKeyVaultSecret `
                    -VaultName $VaultName `
                    -Name $SecretName `
                    -ErrorAction Stop

                if (
                    $null -ne $Secret -and
                    $null -ne $Secret.SecretValue
                ) {
                    Write-Log (
                        "Secret '$SecretName' retrieved successfully " +
                        "on attempt $Attempt."
                    )

                    break
                }

                $Secret = $null
                $LastRetrievalError = (
                    "Key Vault returned no secret value for '$SecretName'."
                )

                Write-Log $LastRetrievalError -Level "WARNING"
            }
            catch {
                $LastRetrievalError = $_.Exception.Message

                $StatusCode = Get-ExceptionHttpStatusCode `
                    -Exception $_.Exception

                switch ($StatusCode) {
                    401 {
                        Write-Log (
                            "Fatal Key Vault error: HTTP 401 Unauthorized. " +
                            "The request was not authenticated."
                        ) -Level "ERROR"

                        $FatalKeyVaultError = $true
                    }

                    403 {
                        Write-Log (
                            "Fatal Key Vault error: HTTP 403 Forbidden. " +
                            "The managed identity is not authorized, or " +
                            "Key Vault network controls denied the request."
                        ) -Level "ERROR"

                        $FatalKeyVaultError = $true
                    }

                    default {
                        Write-Log (
                            "Attempt $Attempt failed: " +
                            $LastRetrievalError
                        ) -Level "WARNING"
                    }
                }

                if ($FatalKeyVaultError) {
                    break
                }
            }

            #
            # Do not sleep after the final attempt.
            #
            if ($Attempt -ge $MaxAttempts) {
                break
            }

            $RemainingSeconds = :Floor(
                $TimeoutSeconds - $Stopwatch.Elapsed.TotalSeconds
            )

            if ($RemainingSeconds -le 0) {
                Write-Log (
                    "Overall Key Vault polling timeout of $TimeoutSeconds " +
                    "seconds was reached."
                ) -Level "ERROR"

                break
            }

            $SleepSeconds = :Min(
                $RetryDelaySeconds,
                [int]$RemainingSeconds
            )

            if ($SleepSeconds -gt 0) {
                Write-Log (
                    "Waiting $SleepSeconds seconds before the next " +
                    "Key Vault retrieval attempt."
                )

                Start-Sleep -Seconds $SleepSeconds
            }
        }

        if ($null -ne $Stopwatch) {
            $Stopwatch.Stop()
        }

        #
        # -------------------------------------------------------------------
        # Validate retrieval result
        # -------------------------------------------------------------------
        #

        if ($FatalKeyVaultError) {
            throw (
                "Key Vault retrieval stopped because Azure returned " +
                "HTTP 401 or HTTP 403. Review managed identity authentication, " +
                "Key Vault permissions, and Key Vault network controls."
            )
        }

        if (
            $null -eq $Secret -or
            $null -eq $Secret.SecretValue
        ) {
            $TotalElapsedSeconds = :Round(
                $Stopwatch.Elapsed.TotalSeconds,
                2
            )

            $FailureMessage = (
                "Unable to retrieve secret '$SecretName' from vault " +
                "'$VaultName' after $AttemptsPerformed attempt(s) and " +
                "$TotalElapsedSeconds seconds."
            )

            if (-not [string]::Is {
                $FailureMessage += " Last error: $LastRetrievalError"
            }

            Write-Log $FailureMessage -Level "ERROR"

            throw (
                "Unable to retrieve Key Vault secret '$SecretName'. " +
                "Review log file '$LogFile'."
            )
        }

        #
        # Preserve the secret as a SecureString.
        #
        $AccountPassword = $Secret.SecretValue

        #
        # -------------------------------------------------------------------
        # Create service account
        # -------------------------------------------------------------------
        #

        Write-Log "Creating Active Directory service account '$ServiceAccountName'."

        try {
            $ServiceAccount = New-ADUser `
                -Name $ServiceAccountName `
                -SamAccountName $ServiceAccountName `
                -UserPrincipalName "$ServiceAccountName@$DnsRoot" `
                -AccountPassword $AccountPassword `
                -Enabled $true `
                -PasswordNeverExpires $false `
                -CannotChangePassword $false `
                -PassThru `
                -ErrorAction Stop
        }
        catch {
            throw (
                "Failed to create service account '{0}': {1}" -f
                $ServiceAccountName,
                $_.Exception.Message
            )
        }

        Write-Log "Service account created successfully."

        #
        # Release references to the Key Vault secret as soon as account
        # creation is complete.
        #
        $AccountPassword = $null
        $Secret = $null
    }

    #
    # -----------------------------------------------------------------------
    # Retrieve service-account SID
    # -----------------------------------------------------------------------
    #

    Write-Log "Retrieving the service account SID."

    try {
        $ServiceAccount = Get-ADUser `
            -Identity $ServiceAccountName `
            -Properties SID `
            -ErrorAction Stop
    }
    catch {
        throw (
            "Unable to retrieve service account '{0}': {1}" -f
            $ServiceAccountName,
            $_.Exception.Message
        )
    }

    if ($null -eq $ServiceAccount.SID) {
        throw "No SID was returned for service account '$ServiceAccountName'."
    }

    $SID = [System.Security.Principal.SecurityIdentifier]$ServiceAccount.SID

    Write-Log "Service account SID retrieved successfully: $($SID.Value)"

    #
    # -----------------------------------------------------------------------
    # Retrieve Computer object schema GUID
    # -----------------------------------------------------------------------
    #

    Write-Log "Retrieving the Active Directory Computer object schema GUID."

    try {
        $RootDSE = Get-ADRootDSE -ErrorAction Stop

        $ComputerSchema = Get-ADObject `
            -SearchBase $RootDSE.SchemaNamingContext `
            -LDAPFilter "(lDAPDisplayName=computer)" `
            -Properties schemaIDGUID `
            -ErrorAction Stop
    }
    catch {
        throw (
            "Unable to retrieve the Computer object schema GUID: {0}" -f
            $_.Exception.Message
        )
    }

    if (
        $null -eq $ComputerSchema -or
        $null -eq $ComputerSchema.schemaIDGUID
    ) {
        throw "The Computer object schema definition could not be located."
    }

    $ComputerObjectGuid = New-Object `
        -TypeName System.Guid `
        -ArgumentList (,$ComputerSchema.schemaIDGUID)

    Write-Log "Computer object schema GUID retrieved: $ComputerObjectGuid"

    #
    # -----------------------------------------------------------------------
    # Read target OU ACL
    # -----------------------------------------------------------------------
    #

    $OUPath = "AD:\$ComputerOU"

    Write-Log "Reading the ACL for '$ComputerOU'."

    try {
        $ACL = Get-Acl `
            -Path $OUPath `
            -ErrorAction Stop
    }
    catch {
        throw (
            "Unable to read the ACL for '{0}': {1}" -f
            $ComputerOU,
            $_.Exception.Message
        )
    }

    $Identity = New-Object `
        -TypeName System.Security.Principal.SecurityIdentifier `
        -ArgumentList $SID.Value

    #
    # -----------------------------------------------------------------------
    # Build the Create Computer Objects ACE
    # -----------------------------------------------------------------------
    #

    $CreateComputerRule = New-Object `
        -TypeName System.DirectoryServices.ActiveDirectoryAccessRule `
        -ArgumentList @(
            $Identity,
            [System.DirectoryServices.ActiveDirectoryRights]::CreateChild,
            [System.Security.AccessControl.AccessControlType]::Allow,
            $ComputerObjectGuid,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::None
        )

    #
    # -----------------------------------------------------------------------
    # Detect an equivalent existing ACE
    # -----------------------------------------------------------------------
    #

    Write-Log "Checking for an existing Create Computer Objects delegation."

    $ExistingRule = $ACL.Access | Where-Object {
        $ExistingSID = $null

        try {
            $ExistingSID = $_.IdentityReference.Translate(
                [System.Security.Principal.SecurityIdentifier]
            )
        }
        catch {
            Write-Verbose (
                "Unable to translate ACL identity '{0}' to a SID." -f
                $_.IdentityReference
            )
        }

        $HasCreateChild = (
            (
                $_.ActiveDirectoryRights -band
                [System.DirectoryServices.ActiveDirectoryRights]::CreateChild
            ) -eq
            [System.DirectoryServices.ActiveDirectoryRights]::CreateChild
        )

        $SIDMatches = (
            $null -ne $ExistingSID -and
            $ExistingSID.Value -eq $SID.Value
        )

        $SIDMatches -and
        $HasCreateChild -and
        $_.AccessControlType -eq `
            [System.Security.AccessControl.AccessControlType]::Allow -and
        $_.ObjectType -eq $ComputerObjectGuid
    } | Select-Object -First 1

    if ($null -ne $ExistingRule) {
        Write-Log (
            "Create Computer Objects delegation already exists. " +
            "ACL update skipped."
        ) -Level "WARNING"
    }
    else {
        Write-Log "Adding Create Computer Objects delegation."

        $ACL.AddAccessRule($CreateComputerRule)

        try {
            Set-Acl `
                -Path $OUPath `
                -AclObject $ACL `
                -ErrorAction Stop
        }
        catch {
            throw (
                "Unable to update the ACL for '{0}': {1}" -f
                $ComputerOU,
                $_.Exception.Message
            )
        }

        Write-Log "OU delegation added successfully."
    }

    #
    # -----------------------------------------------------------------------
    # Completion summary
    # -----------------------------------------------------------------------
    #

    Write-Log "Linux Active Directory prestaging configuration completed successfully."

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Linux AD Prestaging Configuration"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host "Account: $ServiceAccountName"
    Write-Host "UPN:     $ServiceAccountName@$DnsRoot"
    Write-Host "SID:     $($SID.Value)"
    Write-Host "OU:      $ComputerOU"
    Write-Host "Rights:  Create Computer Objects"
    Write-Host "Log:     $LogFile"
    Write-Host ""
    Write-Host "Configuration completed successfully." `
        -ForegroundColor Green
}
catch {
    Write-Log `
        "Configuration failed: $($_.Exception.Message)" `
        -Level "ERROR"

    throw
}
finally {
    #
    # Release sensitive-object references.
    #
    $AccountPassword = $null
    $Secret = $null

    if ($null -ne $Stopwatch -and $Stopwatch.IsRunning) {
        $Stopwatch.Stop()
    }

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
