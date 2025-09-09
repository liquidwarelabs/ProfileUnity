# Core\Authentication.ps1 - Authentication and Connection Functions
# Relative Path: \Core\Authentication.ps1
# Self-contained - no dependencies on other module files

# =============================================================================
# AUTHENTICATION AND CONNECTION FUNCTIONS
# =============================================================================

# Get-ProfileUnityCredential moved to Core/Connection.ps1 to avoid duplication

# Set-TrustAllCertsPolicy moved to Core/Connection.ps1 to avoid duplication

# Test-ProfileUnityConnection moved to Core/Connection.ps1 to avoid duplication

# Connect-ProfileUnityServer moved to Core/Connection.ps1 to avoid duplication

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
    
    if (Test-ProfileUnityConnection) {
        # Clear module configuration
        $script:ModuleConfig.Session = $null
        $script:ModuleConfig.ServerName = $null
        $script:ModuleConfig.BaseUrl = $null
        
        # Clear current items
        $script:ModuleConfig.CurrentItems = @{
            Config = $null
            Filter = $null
            PortRule = $null
            FlexApp = $null
        }
        
        # Clear global variables
        $global:session = $null
        $global:servername = $null
        $global:CurrentConfig = $null
        $global:CurrentFilter = $null
        $global:CurrentPortRule = $null
        $global:CurrentFlexapp = $null
        
        Write-Host "Disconnected from ProfileUnity server" -ForegroundColor Yellow
    }
    else {
        Write-Host "No active connection to disconnect" -ForegroundColor Yellow
    }
}

function Get-ProfileUnityConnectionStatus {
    <#
    .SYNOPSIS
        Gets detailed connection status information.
    
    .DESCRIPTION
        Returns detailed information about the current ProfileUnity connection.
    
    .EXAMPLE
        Get-ProfileUnityConnectionStatus
    #>
    [CmdletBinding()]
    param()
    
    $status = [PSCustomObject]@{
        Connected = $false
        ServerName = $null
        BaseUrl = $null
        SessionExists = $false
        GlobalVariablesSet = $false
        ConnectionTime = $null
    }
    
    # Check module config
    if ($script:ModuleConfig.Session -and $script:ModuleConfig.ServerName) {
        $status.Connected = $true
        $status.ServerName = $script:ModuleConfig.ServerName
        $status.BaseUrl = $script:ModuleConfig.BaseUrl
        $status.SessionExists = $true
    }
    
    # Check global variables
    if ($global:session -and $global:servername) {
        $status.GlobalVariablesSet = $true
        if (-not $status.Connected) {
            $status.Connected = $true
            $status.ServerName = $global:servername
            $status.BaseUrl = "https://$($global:servername):8000/api"
        }
    }
    
    return $status
}

# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
# Export-ModuleMember removed to prevent conflicts when dot-sourcing