<#
.SYNOPSIS
  Back up ProfileUnity database (scheduled-task friendly)

.DESCRIPTION
  Authenticates to a ProfileUnity server, triggers a DB backup,
  waits for completion, downloads the newest backup, verifies the file,
  logs out, and tracks total execution time.

.NOTES
  Version:        5.4
  Changes:        Added execution timer to track backup duration.
#>

[CmdletBinding()]
Param(
  [Parameter(Mandatory = $true)]
  [string]$ServerName,

  [Parameter(Mandatory = $true)]
  [string]$User,

  [Parameter(Mandatory = $false)]
  [string]$PasswordFileLocation,

  [Parameter(Mandatory = $false)]
  [string]$AESKeyFileLocation,

  [Parameter(Mandatory = $false)]
  [string]$SavePath,

  [Parameter(Mandatory = $false)]
  [switch]$PurgeOld,

  [Parameter(Mandatory = $false)]
  [int]$BackupCount = 3
)

# Start the clock
$StartTime = Get-Date

$script:ServerName = $ServerName
$script:User = $User
$here = if ($PSScriptRoot) { $PSScriptRoot } else { $pwd.Path }

if (-not $PasswordFileLocation) { $PasswordFileLocation = Join-Path $here 'password.enc' }
if (-not $AESKeyFileLocation)   { $AESKeyFileLocation   = Join-Path $here 'aeskey.bin'   }
if (-not $SavePath)             { $SavePath             = $here }

if (-not (Test-Path $PasswordFileLocation)) { throw "Password file not found: $PasswordFileLocation" }
if (-not (Test-Path $AESKeyFileLocation))   { throw "AES key file not found: $AESKeyFileLocation" }
if (-not (Test-Path $SavePath)) { New-Item -ItemType Directory -Path $SavePath -Force | Out-Null }

$keyBytes   = Get-Content -Path $AESKeyFileLocation -Encoding Byte
$cipherText = Get-Content -Path $PasswordFileLocation -Raw
$securePass = ConvertTo-SecureString -String $cipherText -Key $keyBytes

add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
  public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
    return true;
  }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$plainPassPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
try {
  $plainPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto($plainPassPtr)
}
finally {
  if ($plainPassPtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($plainPassPtr) }
}

# --- 1. Authenticate
$authUri = "https://$($script:ServerName):8000/authenticate"
Write-Host "Logging into ProfileUnity server: $authUri ..." -ForegroundColor Cyan

try {
  Invoke-WebRequest $authUri `
    -Body "username=$($script:User)&password=$plainPass" `
    -Method POST `
    -SessionVariable scriptSession | Out-Null
} catch {
  throw "Authentication failed: $($_.Exception.Message)"
}
$script:session = $scriptSession

# --- 2. Start a backup
Write-Host "Starting backup..."
try {
  $backupUri = "https://$($script:ServerName):8000/api/database/backup"
  Invoke-RestMethod $backupUri -WebSession $script:session -Method GET | Out-Null
} catch {
  throw "Failed to start backup: $($_.Exception.Message)"
}

# --- 3. Poll for completion
Write-Host "Waiting for backup to complete..."
function Get-LatestBackup {
  $listUri = "https://$($script:ServerName):8000/api/database/backup/list"
  $list = Invoke-RestMethod $listUri -WebSession $script:session
  return ($list.Tag | Sort-Object -Property created -Descending | Select-Object -First 1)
}

$latest = Get-LatestBackup
while ($latest.State -eq 'Processing') {
  Start-Sleep -Seconds 5
  $latest = Get-LatestBackup
  Write-Host "  Status: $($latest.State)..."
}

if ($latest.State -ne 'Success') {
  throw "Latest backup did not complete successfully. State: $($latest.State)"
}

# --- 4. Download the ZIP
$destFile = Join-Path $SavePath $latest.Filename
Write-Host "Downloading $($latest.Filename) to '$destFile'..."
try {
  $dlUri = "https://$($script:ServerName):8000/api/database/backup/$($latest.id)"
  Invoke-WebRequest $dlUri -WebSession $script:session -OutFile $destFile | Out-Null
} catch {
  throw "Failed to download backup: $($_.Exception.Message)"
}

# --- 5. Verify the Backup File
Write-Host "Verifying backup file..." -ForegroundColor Cyan
if (Test-Path $destFile) {
    $fileInfo = Get-Item $destFile
    if ($fileInfo.Length -gt 0) {
        Write-Host "Verification Success: File exists ($($fileInfo.Length) bytes)." -ForegroundColor Green
    } else {
        throw "Verification Failed: File exists but is 0 bytes."
    }
} else {
    throw "Verification Failed: Backup file was not found."
}

# --- 6. Explicit Logout
Write-Host "Logging out and closing session..." -ForegroundColor Cyan
try {
    $logoutUri = "https://$($script:ServerName):8000/logout"
    Invoke-WebRequest $logoutUri -WebSession $script:session -Method GET -ErrorAction SilentlyContinue | Out-Null
} finally {
    $script:session = $null
    $scriptSession = $null
    Remove-Variable -Name scriptSession -Scope Global -ErrorAction SilentlyContinue
}

# --- 7. Purge older local backups
if ($PurgeOld) {
  Write-Host "Purging older local backups..."
  $localBackups = Get-ChildItem -Path $SavePath -Filter '*.zip' | Sort-Object -Property LastWriteTime -Descending
  if ($localBackups.Count -gt $BackupCount) {
    $toDelete = $localBackups | Select-Object -Last ($localBackups.Count - $BackupCount)
    $toDelete | Remove-Item -Force
  }
}

# --- 8. Final Timing Report
$EndTime = Get-Date
$Duration = $EndTime - $StartTime
$TimeDisplay = "{0:mm} min {0:ss} sec" -f $Duration

Write-Host "`n========================================" -ForegroundColor Gray
Write-Host "Backup process finished successfully." -ForegroundColor Green
Write-Host "Total Duration: $TimeDisplay" -ForegroundColor Yellow
Write-Host "Saved to: $destFile"
Write-Host "========================================`n" -ForegroundColor Gray