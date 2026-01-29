# Where to save files: prefer the script's folder; fall back to current directory in console
$here = if ($PSScriptRoot) { $PSScriptRoot } else { $pwd.Path }

# Prompt for creds and grab the SecureString password
$credObject            = Get-Credential
$passwordSecureString  = $credObject.Password

# File paths beside the script / current folder
$AESKeyFilePath        = Join-Path $here 'aeskey.bin'
$credentialFilePath    = Join-Path $here 'password.enc'

# Generate a 256-bit AES key
$AESKey = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($AESKey)

# Save the key as raw bytes (use -Encoding Byte!)
Set-Content -Path $AESKeyFilePath -Value $AESKey -Encoding Byte   # overwrites if exists

# Encrypt the SecureString with the key and save ciphertext as text
$encrypted = $passwordSecureString | ConvertFrom-SecureString -Key $AESKey
Set-Content -Path $credentialFilePath -Value $encrypted -Encoding UTF8  # overwrites if exists

Write-Host "Saved:"
Write-Host "  Key: $AESKeyFilePath"
Write-Host "  Encrypted password: $credentialFilePath"
