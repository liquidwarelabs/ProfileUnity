# Test script to examine Policy structure in RegistrySettings
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

# Examine RegistrySettings extension
Write-Host "`nExamining RegistrySettings extension..." -ForegroundColor Yellow

if ($gpoXml.GPO.Computer) {
    $computerExtensions = $gpoXml.GPO.Computer.ExtensionData
    if ($computerExtensions) {
        foreach ($extensionData in $computerExtensions) {
            if ($extensionData.Extension) {
                $extensions = if ($extensionData.Extension -is [array]) { $extensionData.Extension } else { @($extensionData.Extension) }
                foreach ($extension in $extensions) {
                    if ($extension.type -like "*RegistrySettings*") {
                        Write-Host "Found RegistrySettings extension: $($extension.type)" -ForegroundColor Green
                        Write-Host "  Extension properties: $($extension | Get-Member -MemberType Property | Select-Object -ExpandProperty Name)" -ForegroundColor Gray
                        
                        if ($extension.Policy) {
                            Write-Host "  Policy exists: True" -ForegroundColor Green
                            Write-Host "  Policy type: $($extension.Policy.GetType().Name)" -ForegroundColor Gray
                            
                            if ($extension.Policy -is [array]) {
                                Write-Host "  Policy is array with $($extension.Policy.Count) items" -ForegroundColor Gray
                                foreach ($policy in $extension.Policy) {
                                    Write-Host "    Policy properties: $($policy | Get-Member -MemberType Property | Select-Object -ExpandProperty Name)" -ForegroundColor Gray
                                    if ($policy.Name) {
                                        Write-Host "    Policy Name: $($policy.Name)" -ForegroundColor Green
                                    }
                                }
                            } else {
                                Write-Host "  Policy is single object" -ForegroundColor Gray
                                Write-Host "  Policy properties: $($extension.Policy | Get-Member -MemberType Property | Select-Object -ExpandProperty Name)" -ForegroundColor Gray
                                if ($extension.Policy.Name) {
                                    Write-Host "  Policy Name: $($extension.Policy.Name)" -ForegroundColor Green
                                }
                            }
                        } else {
                            Write-Host "  Policy does not exist" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
    }
}

Write-Host "`nTest completed!" -ForegroundColor Green

