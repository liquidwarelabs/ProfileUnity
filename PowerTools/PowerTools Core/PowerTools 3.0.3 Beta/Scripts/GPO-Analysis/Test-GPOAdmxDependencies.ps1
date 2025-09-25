# Test script to isolate ExtensionData issue
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$GpoDisplayName
)

try {
    Import-Module GroupPolicy -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "Required modules imported successfully" -ForegroundColor Green
} catch {
    throw "Failed to import required modules: $($_.Exception.Message)"
}

# Get GPO
Write-Host "Retrieving GPO information..." -ForegroundColor Yellow
try {
    $gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
    Write-Host "GPO found: $GpoDisplayName (ID: $($gpo.Id))" -ForegroundColor Green
} catch {
    throw "GPO '$GpoDisplayName' not found: $($_.Exception.Message)"
}

# Generate GPO report
Write-Host "Generating GPO report..." -ForegroundColor Yellow
try {
    $gpoReport = Get-GPOReport -Name $GpoDisplayName -ReportType Xml -ErrorAction Stop
    $gpoXml = [xml]$gpoReport
    Write-Host "GPO report generated successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to generate GPO report: $($_.Exception.Message)"
    return
}

# Debug XML structure
Write-Host "`nDebug: Checking XML structure..." -ForegroundColor Yellow
Write-Host "  GPO.Computer exists: $($gpoXml.GPO.Computer -ne $null)" -ForegroundColor Gray
Write-Host "  GPO.User exists: $($gpoXml.GPO.User -ne $null)" -ForegroundColor Gray

if ($gpoXml.GPO.Computer) {
    Write-Host "  Computer.ExtensionData exists: $($gpoXml.GPO.Computer.ExtensionData -ne $null)" -ForegroundColor Gray
    if ($gpoXml.GPO.Computer.ExtensionData) {
        Write-Host "  Computer.ExtensionData count: $($gpoXml.GPO.Computer.ExtensionData.Count)" -ForegroundColor Gray
        Write-Host "  Computer.ExtensionData type: $($gpoXml.GPO.Computer.ExtensionData.GetType().Name)" -ForegroundColor Gray
        
        # Test accessing each ExtensionData
        for ($i = 0; $i -lt $gpoXml.GPO.Computer.ExtensionData.Count; $i++) {
            Write-Host "    ExtensionData[$i] type: $($gpoXml.GPO.Computer.ExtensionData[$i].GetType().Name)" -ForegroundColor Gray
            if ($gpoXml.GPO.Computer.ExtensionData[$i].Extension) {
                Write-Host "      Extension exists: True" -ForegroundColor Gray
                Write-Host "      Extension type: $($gpoXml.GPO.Computer.ExtensionData[$i].Extension.GetType().Name)" -ForegroundColor Gray
                if ($gpoXml.GPO.Computer.ExtensionData[$i].Extension.type) {
                    Write-Host "      Extension.type: $($gpoXml.GPO.Computer.ExtensionData[$i].Extension.type)" -ForegroundColor Gray
                }
            }
        }
    }
}

Write-Host "`nTest completed successfully!" -ForegroundColor Green

