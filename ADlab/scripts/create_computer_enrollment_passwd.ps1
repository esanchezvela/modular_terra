$bytes = New-Object byte[] 32 
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes) 
$EnrollmentSecret = [System.Convert]::ToBase64String($bytes)
$SecurePassword = ConvertTo-SecureString $EnrollmentSecret -AsPlainText -Force 

Set-ADAccountPassword `
  -Identity "$ComputerName`$" `
  -Reset `
  -NewPassword $SecurePassword
