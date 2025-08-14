# Authentication.ps1 - ProfileUnity Authentication Functions

function Connect-ProfileUnityServer {
    <#
    .SYNOPSIS
        Connects to a ProfileUnity server and establishes an authenticated session.
    
    .DESCRIPTION
        Authenticates to a ProfileUnity server using username/password credentials.
        Stores the session for subsequent API calls.
    
    .PARAMETER ServerName
        FQDN of the ProfileUnity server
    
    .PARAMETER Username
        Username for authentication
    
    .PARAMETER Password
        Password for authentication
    
    .PARAMETER Port
        Port number (default: 8000)
    
    .PARAMETER EnforceSSLValidation
        If specified, enforces SSL certificate validation
    
    .EXAMPLE
        Connect-ProfileUnityServer -ServerName "profileunity.domain.com"
        
    .EXAMPLE
        Connect-ProfileUnityServer -ServerName "profileunity.domain.com" -Username "admin" -Password "password"
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [string]$ServerName,
        
        [Parameter(ParameterSetName = 'PlainText')]
        [string]$Username,
        
        [Parameter(ParameterSetName = 'PlainText')]
        [string]$Password,
        
        [int]$Port = 8000,
        
        [switch]$EnforceSSLValidation
    )
    
    try {
        # Get server name if not provided
        if (-not $ServerName) {
            $ServerName = Read-Host -Prompt 'Enter FQDN of ProfileUnity Server'
            if ([string]::IsNullOrWhiteSpace($ServerName)) {
                throw "Server name cannot be empty"
            }
        }
        
        # Get credentials
        $Credential = Get-ProfileUnityCredential -Username $Username -Password $Password
        
        # Configure SSL
        if (-not $EnforceSSLValidation) {
            Set-TrustAllCertsPolicy
        }
        
        # Set TLS protocols
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        
        # Build authentication URL and body
        $authUrl = "https://${ServerName}:${Port}/authenticate"
        $authBody = "username=$($Credential.UserName)&password=$($Credential.GetNetworkCredential().Password)"
        
        Write-Verbose "Authenticating to: $authUrl"
        
        # Authenticate
        $response = Invoke-WebRequest -Uri $authUrl -Method POST -Body $authBody -SessionVariable webSession -TimeoutSec 30
        
        if ($response.StatusCode -eq 200) {
            # Store session information
            $script:ModuleConfig.Session = $webSession
            $script:ModuleConfig.ServerName = $ServerName
            $script:ModuleConfig.Port = $Port
            $script:ModuleConfig.BaseUrl = "https://${ServerName}:${Port}/api"
            $script:ModuleConfig.Connected = $true
            $script:ModuleConfig.ConnectedAt = Get-Date
            
            # Also set global variables for backward compatibility
            $global:session = $webSession
            $global:servername = $ServerName
            
            Write-Host "Successfully connected to ProfileUnity server: $ServerName" -ForegroundColor Green
            
            return [PSCustomObject]@{
                ServerName = $ServerName
                Port = $Port
                Connected = $true
                AuthenticationTime = Get-Date
                SessionCookie = $webSession.Cookies.GetCookies($authUrl)
            }
        }
        
        throw "Authentication failed with status code: $($response.StatusCode)"
    }
    catch {
        Write-Error "Connection failed: $($_.Exception.Message)"
        throw
    }
}

function Disconnect-ProfileUnityServer {
    <#
    .SYNOPSIS
        Disconnects from the ProfileUnity server and clears the session.
    
    .DESCRIPTION
        Clears the stored session information and resets connection state.
    
    .EXAMPLE
        Disconnect-ProfileUnityServer
    #>
    [CmdletBinding()]
    param()
    
    if ($script:ModuleConfig.Connected) {
        # Clear module configuration
        $script:ModuleConfig.Session = $null
        $script:ModuleConfig.ServerName = $null
        $script:ModuleConfig.Port = $null
        $script:ModuleConfig.BaseUrl = $null
        $script:ModuleConfig.Connected = $false
        $script:ModuleConfig.ConnectedAt = $null
        
        # Clear global variables
        $global:session = $null
        $global:servername = $null
        
        # Clear current items
        $script:ModuleConfig.CurrentItems = @{
            Config = $null
            Filter = $null
            PortRule = $null
            FlexApp = $null
        }
        
        Write-Host "Disconnected from ProfileUnity server" -ForegroundColor Yellow
    }
    else {
        Write-Host "No active connection to disconnect" -ForegroundColor Yellow
    }
}

function Test-ProfileUnityConnection {
    <#
    .SYNOPSIS
        Tests if there is an active connection to a ProfileUnity server.
    
    .DESCRIPTION
        Checks if a valid session exists and optionally performs a heartbeat check.
    
    .PARAMETER Detailed
        If specified, performs an actual API call to verify the connection is alive.
    
    .EXAMPLE
        Test-ProfileUnityConnection
        
    .EXAMPLE
        Test-ProfileUnityConnection -Detailed
    #>
    [CmdletBinding()]
    param(
        [switch]$Detailed
    )
    
    # Check basic connection state
    if (-not (($script:ModuleConfig.Session -and $script:ModuleConfig.ServerName) -or 
             ($global:session -and $global:servername))) {
        Write-Host "No active connection found" -ForegroundColor Yellow
        return $false
    }
    
    $serverName = if ($script:ModuleConfig.ServerName) { 
        $script:ModuleConfig.ServerName 
    } else { 
        $global:servername 
    }
    
    if ($Detailed) {
        try {
            # Try to call the authenticated endpoint
            $response = Invoke-ProfileUnityApi -Endpoint "authenticated" -Method GET -ErrorAction Stop
            
            if ($response) {
                Write-Host "Connection active and authenticated to: $serverName" -ForegroundColor Green
                return $true
            }
        }
        catch {
            Write-Host "Connection test failed: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "Connection active to: $serverName" -ForegroundColor Green
        
        if ($script:ModuleConfig.ConnectedAt) {
            $duration = (Get-Date) - $script:ModuleConfig.ConnectedAt
            Write-Host "Connected for: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Gray
        }
        
        return $true
    }
}

function Get-ProfileUnityCredential {
    <#
    .SYNOPSIS
        Gets credentials for ProfileUnity authentication.
    
    .DESCRIPTION
        Internal function to handle credential collection for authentication.
    
    .PARAMETER Username
        Username if provided
    
    .PARAMETER Password
        Password if provided
    #>
    [CmdletBinding()]
    param(
        [string]$Username,
        [string]$Password
    )
    
    if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
        Write-Host "Please enter your ProfileUnity credentials:" -ForegroundColor Yellow
        
        if ([string]::IsNullOrWhiteSpace($Username)) {
            $Username = Read-Host -Prompt "Username"
        }
        
        $SecurePassword = Read-Host -Prompt "Password for $Username" -AsSecureString
        return New-Object System.Management.Automation.PSCredential($Username, $SecurePassword)
    }
    
    $securePass = ConvertTo-SecureString -String $Password -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($Username, $securePass)
}

function Set-TrustAllCertsPolicy {
    <#
    .SYNOPSIS
        Configures PowerShell to bypass SSL certificate validation.
    
    .DESCRIPTION
        Internal function to disable SSL certificate validation for self-signed certificates.
    #>
    [CmdletBinding()]
    param()
    
    Write-Verbose "SSL certificate validation will be bypassed"
    
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class TrustAllCertsPolicy : ICertificatePolicy {
                public bool CheckValidationResult(
                    ServicePoint srvPoint, X509Certificate certificate,
                    WebRequest request, int certificateProblem) {
                    return true;
                }
            }
"@
    }
    
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

function Get-ProfileUnitySession {
    <#
    .SYNOPSIS
        Gets the current ProfileUnity session information.
    
    .DESCRIPTION
        Returns details about the current connection session.
    
    .EXAMPLE
        Get-ProfileUnitySession
    #>
    [CmdletBinding()]
    param()
    
    if (-not $script:ModuleConfig.Connected) {
        Write-Warning "No active ProfileUnity session"
        return $null
    }
    
    return [PSCustomObject]@{
        ServerName = $script:ModuleConfig.ServerName
        Port = $script:ModuleConfig.Port
        BaseUrl = $script:ModuleConfig.BaseUrl
        Connected = $script:ModuleConfig.Connected
        ConnectedAt = $script:ModuleConfig.ConnectedAt
        Duration = if ($script:ModuleConfig.ConnectedAt) { 
            (Get-Date) - $script:ModuleConfig.ConnectedAt 
        } else { 
            $null 
        }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Connect-ProfileUnityServer',
    'Disconnect-ProfileUnityServer',
    'Test-ProfileUnityConnection',
    'Get-ProfileUnitySession'
)