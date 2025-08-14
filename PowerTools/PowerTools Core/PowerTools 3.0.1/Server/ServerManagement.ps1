# ServerManagement.ps1 - ProfileUnity Server Management Functions

function Get-ProUServerSettings {
    <#
    .SYNOPSIS
        Gets ProfileUnity server settings.
    
    .DESCRIPTION
        Retrieves server configuration settings.
    
    .PARAMETER Setting
        Specific setting name to retrieve
    
    .PARAMETER Property
        Specific property of a setting
    
    .EXAMPLE
        Get-ProUServerSettings
        
    .EXAMPLE
        Get-ProUServerSettings -Setting "General" -Property "ServerName"
    #>
    [CmdletBinding()]
    param(
        [string]$Setting,
        [string]$Property
    )
    
    try {
        if ($Setting -and $Property) {
            $endpoint = "server/setting/$Setting/$Property"
        }
        elseif ($Setting) {
            $endpoint = "server/setting/$Setting"
        }
        else {
            $endpoint = "server/setting"
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint $endpoint
        
        if ($response) {
            return $response
        }
    }
    catch {
        Write-Error "Failed to get server settings: $_"
        throw
    }
}

function Set-ProUServerSetting {
    <#
    .SYNOPSIS
        Sets a ProfileUnity server setting.
    
    .DESCRIPTION
        Updates server configuration settings.
    
    .PARAMETER Setting
        Setting category name
    
    .PARAMETER Property
        Property name to set
    
    .PARAMETER Value
        Value to set
    
    .EXAMPLE
        Set-ProUServerSetting -Setting "General" -Property "ServerName" -Value "MyServer"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Setting,
        
        [Parameter(Mandatory)]
        [string]$Property,
        
        [Parameter(Mandatory)]
        [string]$Value
    )
    
    try {
        $endpoint = "server/setting/$Setting/$Property"
        $body = @{ value = $Value }
        
        $response = Invoke-ProfileUnityApi -Endpoint $endpoint -Method POST -Body $body
        
        if ($response) {
            Write-Host "Server setting updated: $Setting.$Property = $Value" -ForegroundColor Green
            return $response
        }
    }
    catch {
        Write-Error "Failed to set server setting: $_"
        throw
    }
}

function Get-ProUServerAbout {
    <#
    .SYNOPSIS
        Gets ProfileUnity server information.
    
    .DESCRIPTION
        Retrieves server version and system information.
    
    .EXAMPLE
        Get-ProUServerAbout
    #>
    [CmdletBinding()]
    param()
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "server/about"
        
        if ($response) {
            return [PSCustomObject]@{
                Version = $response.version
                BuildNumber = $response.buildNumber
                ServerName = $response.serverName
                InstallPath = $response.installPath
                DatabaseVersion = $response.databaseVersion
                LicenseInfo = $response.licenseInfo
                SystemInfo = $response.systemInfo
            }
        }
    }
    catch {
        Write-Error "Failed to get server information: $_"
        throw
    }
}

function Get-ProUServerCertificates {
    <#
    .SYNOPSIS
        Gets server SSL certificates.
    
    .DESCRIPTION
        Retrieves information about server SSL certificates.
    
    .PARAMETER Location
        Certificate location (LocalMachine, CurrentUser)
    
    .PARAMETER Name
        Certificate name/thumbprint
    
    .EXAMPLE
        Get-ProUServerCertificates
    #>
    [CmdletBinding()]
    param(
        [string]$Location,
        [string]$Name
    )
    
    try {
        $endpoint = if ($Location -and $Name) {
            "server/certificate/$Location/$Name"
        } else {
            "server/certificate"
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint $endpoint
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Thumbprint = $_.thumbprint
                    Subject = $_.subject
                    Issuer = $_.issuer
                    NotBefore = $_.notBefore
                    NotAfter = $_.notAfter
                    HasPrivateKey = $_.hasPrivateKey
                    Location = $_.location
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get server certificates: $_"
        throw
    }
}

function Add-ProUServerCertificate {
    <#
    .SYNOPSIS
        Adds a new SSL certificate to the server.
    
    .DESCRIPTION
        Imports and configures an SSL certificate for the ProfileUnity server.
    
    .PARAMETER CertificateFile
        Path to certificate file (.pfx/.p12)
    
    .PARAMETER Password
        Certificate password
    
    .PARAMETER SetAsDefault
        Set as default certificate
    
    .EXAMPLE
        Add-ProUServerCertificate -CertificateFile "C:\cert.pfx" -Password "password"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CertificateFile,
        
        [string]$Password,
        
        [switch]$SetAsDefault
    )
    
    try {
        if (-not (Test-Path $CertificateFile)) {
            throw "Certificate file not found: $CertificateFile"
        }
        
        # Read certificate file
        $certBytes = [System.IO.File]::ReadAllBytes($CertificateFile)
        $certBase64 = [Convert]::ToBase64String($certBytes)
        
        $body = @{
            certificateData = $certBase64
            fileName = Split-Path $CertificateFile -Leaf
            password = $Password
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "server/certificate/add" -Method POST -Body $body
        
        if ($response -and $SetAsDefault) {
            $null = Invoke-ProfileUnityApi -Endpoint "server/certificate/default" -Method POST -Body @{
                thumbprint = $response.thumbprint
            }
            Write-Host "Certificate set as default" -ForegroundColor Green
        }
        
        Write-Host "Certificate imported successfully" -ForegroundColor Green
        return $response
    }
    catch {
        Write-Error "Failed to add server certificate: $_"
        throw
    }
}

function Deploy-ProUConfiguration {
    <#
    .SYNOPSIS
        Deploys a configuration to client computers.
    
    .DESCRIPTION
        Triggers deployment of configuration scripts to endpoints.
    
    .PARAMETER ConfigurationName
        Name of configuration to deploy
    
    .EXAMPLE
        Deploy-ProUConfiguration -ConfigurationName "Windows 10 Standard"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigurationName
    )
    
    if ($PSCmdlet.ShouldProcess($ConfigurationName, "Deploy configuration")) {
        try {
            # Get configuration ID
            $configs = Get-ProUConfig -Name $ConfigurationName
            if (-not $configs) {
                throw "Configuration '$ConfigurationName' not found"
            }
            
            $configId = $configs[0].ID
            
            $response = Invoke-ProfileUnityApi -Endpoint "server/deploy/configuration" -Method POST -Body @{
                configurationId = $configId
            }
            
            if ($response) {
                Write-Host "Configuration deployment initiated: $ConfigurationName" -ForegroundColor Green
                return $response
            }
        }
        catch {
            Write-Error "Failed to deploy configuration: $_"
            throw
        }
    }
}

function Restart-ProUWebServices {
    <#
    .SYNOPSIS
        Restarts ProfileUnity web services.
    
    .DESCRIPTION
        Restarts the ProfileUnity web services on the server.
    
    .EXAMPLE
        Restart-ProUWebServices
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    
    if ($PSCmdlet.ShouldProcess("ProfileUnity Web Services", "Restart")) {
        try {
            $response = Invoke-ProfileUnityApi -Endpoint "server/restartwebservices" -Method POST
            
            Write-Host "Web services restart initiated" -ForegroundColor Green
            Write-Warning "Connection may be temporarily interrupted"
            
            return $response
        }
        catch {
            Write-Error "Failed to restart web services: $_"
            throw
        }
    }
}

function Get-ProUServerUpdate {
    <#
    .SYNOPSIS
        Gets server update status.
    
    .DESCRIPTION
        Checks for available updates and update status.
    
    .EXAMPLE
        Get-ProUServerUpdate
    #>
    [CmdletBinding()]
    param()
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "server/update/status"
        
        if ($response) {
            return [PSCustomObject]@{
                CurrentVersion = $response.currentVersion
                LatestVersion = $response.latestVersion
                UpdateAvailable = $response.updateAvailable
                UpdateStatus = $response.updateStatus
                LastChecked = $response.lastChecked
            }
        }
    }
    catch {
        Write-Error "Failed to get server update status: $_"
        throw
    }
}

function Start-ProUServerUpdate {
    <#
    .SYNOPSIS
        Initiates server update process.
    
    .DESCRIPTION
        Starts the ProfileUnity server update process.
    
    .EXAMPLE
        Start-ProUServerUpdate
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    
    if ($PSCmdlet.ShouldProcess("ProfileUnity Server", "Update")) {
        try {
            $response = Invoke-ProfileUnityApi -Endpoint "server/update/run" -Method POST
            
            Write-Host "Server update initiated" -ForegroundColor Green
            Write-Warning "Server will be unavailable during update"
            
            return $response
        }
        catch {
            Write-Error "Failed to start server update: $_"
            throw
        }
    }
}

function Get-ProUServerVariables {
    <#
    .SYNOPSIS
        Gets server environment variables.
    
    .DESCRIPTION
        Retrieves server environment variables and their values.
    
    .PARAMETER Variable
        Specific variable name to retrieve
    
    .EXAMPLE
        Get-ProUServerVariables
        
    .EXAMPLE
        Get-ProUServerVariables -Variable "TEMP"
    #>
    [CmdletBinding()]
    param(
        [string]$Variable
    )
    
    try {
        $endpoint = if ($Variable) {
            "server/setting/variables/$Variable"
        } else {
            "server/setting/variables"
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint $endpoint
        
        if ($response) {
            if ($Variable) {
                return $response.value
            } else {
                return $response | ForEach-Object {
                    [PSCustomObject]@{
                        Name = $_.name
                        Value = $_.value
                        Source = $_.source
                    }
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get server variables: $_"
        throw
    }
}

function Set-ProUServerServiceAccount {
    <#
    .SYNOPSIS
        Sets the ProfileUnity service account.
    
    .DESCRIPTION
        Updates the service account used by ProfileUnity services.
    
    .PARAMETER Username
        Service account username
    
    .PARAMETER Password
        Service account password
    
    .EXAMPLE
        Set-ProUServerServiceAccount -Username "DOMAIN\serviceaccount" -Password "password"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [Parameter(Mandatory)]
        [string]$Password
    )
    
    if ($PSCmdlet.ShouldProcess($Username, "Set service account")) {
        try {
            $body = @{
                username = $Username
                password = $Password
            }
            
            $response = Invoke-ProfileUnityApi -Endpoint "server/setting/serviceaccount" -Method POST -Body $body
            
            if ($response) {
                Write-Host "Service account updated: $Username" -ForegroundColor Green
                Write-Warning "Service restart may be required"
                return $response
            }
        }
        catch {
            Write-Error "Failed to set service account: $_"
            throw
        }
    }
}

function Test-ProUServerConfiguration {
    <#
    .SYNOPSIS
        Tests server configuration and connectivity.
    
    .DESCRIPTION
        Performs comprehensive server configuration validation.
    
    .EXAMPLE
        Test-ProUServerConfiguration
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "Testing ProfileUnity server configuration..." -ForegroundColor Yellow
        
        $issues = @()
        $warnings = @()
        $info = @{}
        
        # Test basic connectivity
        try {
            $aboutInfo = Get-ProUServerAbout
            $info.Version = $aboutInfo.Version
            $info.ServerName = $aboutInfo.ServerName
            Write-Host "  Server Version: $($aboutInfo.Version)" -ForegroundColor Green
        }
        catch {
            $issues += "Cannot retrieve server information"
        }
        
        # Test certificates
        try {
            $certs = Get-ProUServerCertificates
            if (-not $certs -or $certs.Count -eq 0) {
                $warnings += "No SSL certificates found"
            } else {
                $expiringSoon = $certs | Where-Object { 
                    $_.NotAfter -and (Get-Date $_.NotAfter) -lt (Get-Date).AddDays(30) 
                }
                if ($expiringSoon) {
                    $warnings += "SSL certificates expiring within 30 days: $($expiringSoon.Count)"
                }
                $info.CertificateCount = $certs.Count
            }
        }
        catch {
            $warnings += "Cannot retrieve SSL certificate information"
        }
        
        # Test update status
        try {
            $updateInfo = Get-ProUServerUpdate
            if ($updateInfo.UpdateAvailable) {
                $warnings += "Server update available: $($updateInfo.LatestVersion)"
            }
            $info.UpdateAvailable = $updateInfo.UpdateAvailable
        }
        catch {
            $warnings += "Cannot check update status"
        }
        
        # Display results
        Write-Host "`nServer Configuration Test Results:" -ForegroundColor Cyan
        
        if ($info.Count -gt 0) {
            Write-Host "Server Information:" -ForegroundColor Gray
            $info.GetEnumerator() | ForEach-Object {
                Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
            }
        }
        
        if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
            Write-Host "  No issues found" -ForegroundColor Green
        } else {
            if ($issues.Count -gt 0) {
                Write-Host "  Issues:" -ForegroundColor Red
                $issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            }
            
            if ($warnings.Count -gt 0) {
                Write-Host "  Warnings:" -ForegroundColor Yellow
                $warnings | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
            }
        }
        
        return [PSCustomObject]@{
            ServerInfo = $info
            Issues = $issues
            Warnings = $warnings
            IsHealthy = $issues.Count -eq 0
        }
    }
    catch {
        Write-Error "Failed to test server configuration: $_"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ProUServerSettings',
    'Set-ProUServerSetting', 
    'Get-ProUServerAbout',
    'Get-ProUServerCertificates',
    'Add-ProUServerCertificate',
    'Deploy-ProUConfiguration',
    'Restart-ProUWebServices',
    'Get-ProUServerUpdate',
    'Start-ProUServerUpdate',
    'Get-ProUServerVariables',
    'Set-ProUServerServiceAccount',
    'Test-ProUServerConfiguration'
)