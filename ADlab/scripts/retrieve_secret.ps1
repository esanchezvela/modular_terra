$VaultName  = "kv-linux-domainjoin"
$SecretName = "svc-linux-domainjoin-password"

$MaxAttempts   = 10
$RetryDelay    = 30
$TimeoutSeconds = 300

$LogFile = "C:\Logs\KeyVault-Retrieval.log"

#
# Create log directory if necessary
#
$LogDirectory = Split-Path -Path $LogFile -Parent

if (-not (Test-Path $LogDirectory)) {
    New-Item `
        -ItemType Directory `
        -Path $LogDirectory `
        -Force | Out-Null
}

#
# Logging function
#
function Write-Log {

    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $LogEntry = "$Timestamp [$Level] $Message"

    Add-Content `
        -Path $LogFile `
        -Value $LogEntry

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
# Authenticate with the VM's system-assigned managed identity
#
try {

    Write-Log "Authenticating using Azure VM managed identity."

    Connect-AzAccount `
        -Identity `
        -ErrorAction Stop | Out-Null

    Write-Log "Managed identity authentication successful."

}
catch {

    Write-Log `
        "Managed identity authentication failed: $($_.Exception.Message)" `
        -Level "ERROR"

    throw
}

#
# Start timeout timer
#
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$Secret = $null

#
# Retrieve Key Vault secret
#
for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {

    #
    # Check global timeout before attempting retrieval
    #
    if ($Stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {

        Write-Log `
            "Timeout of $TimeoutSeconds seconds reached before attempt $Attempt." `
            -Level "ERROR"

        break
    }

    try {

        Write-Log `
            "Attempt $Attempt of $MaxAttempts retrieving secret '$SecretName' from vault '$VaultName'."

        $Secret = Get-AzKeyVaultSecret `
            -VaultName $VaultName `
            -Name $SecretName `
            -ErrorAction Stop

        if ($Secret -and $Secret.SecretValue) {

            Write-Log `
                "Secret '$SecretName' retrieved successfully on attempt $Attempt."

            break
        }

        Write-Log `
            "Secret '$SecretName' was not available." `
            -Level "WARNING"
    }
    catch {

        Write-Log `
            "Attempt $Attempt failed: $($_.Exception.Message)" `
            -Level "WARNING"
    }

    #
    # Don't sleep after final attempt.
    #
    if ($Attempt -lt $MaxAttempts) {

        #
        # Determine whether another 30-second sleep would exceed
        # the overall timeout.
        #
        $RemainingSeconds = `
            $TimeoutSeconds - $Stopwatch.Elapsed.TotalSeconds

        if ($RemainingSeconds -le 0) {

            Write-Log `
                "Overall timeout reached." `
                -Level "ERROR"

            break
        }

        $SleepSeconds = :Min(
            $RetryDelay,
            :Floor($RemainingSeconds)
        )

        if ($SleepSeconds -gt 0) {

            Write-Log `
                "Waiting $SleepSeconds seconds before retrying."

            Start-Sleep -Seconds $SleepSeconds
        }
    }
}

$Stopwatch.Stop()

#
# Validate result
#
if (-not $Secret -or -not $Secret.SecretValue) {

    $ElapsedSeconds = :Round(
        $Stopwatch.Elapsed.TotalSeconds,
        2
    )

    Write-Log `
        "Unable to retrieve secret '$SecretName' after $ElapsedSeconds seconds." `
        -Level "ERROR"

    throw "Unable to retrieve Key Vault secret '$SecretName'. See log: $LogFile"
}

#
# Keep the password as SecureString.
# Do NOT convert it to plaintext.
#
$AccountPassword = $Secret.SecretValue

Write-Log "Key Vault secret retrieval completed successfully."
