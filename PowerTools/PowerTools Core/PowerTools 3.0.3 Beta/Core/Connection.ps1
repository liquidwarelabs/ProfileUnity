# Connection.ps1 - ProfileUnity Connection Management and Core API Functions
# Location: \Core\Connection.ps1
# Compatible with: ProfileUnity PowerTools v3.0 / PowerShell 5.1+

function Connect-ProfileUnityServer {
    <#
    .SYNOPSIS
        Connects to a ProfileUnity server and establishes an authenticated session.
    
    .DESCRIPTION
        Authenticates to a ProfileUnity server using username/password credentials with CSRF token handling.
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
        
        Write-Verbose "Connecting to ProfileUnity server: $ServerName"
        
        # Clear existing session
        $script:ModuleConfig.Session = $null
        
        # Step 1: Get login page to obtain fresh CSRF token
        $loginPageUrl = "https://${ServerName}:${Port}"
        Write-Verbose "Getting login page: $loginPageUrl"
        
        $loginPageResponse = Invoke-WebRequest -Uri $loginPageUrl -SessionVariable newSession -TimeoutSec 30
        
        # Step 2: Extract CSRF token from HTML
        $csrfMatch = $loginPageResponse.Content | Select-String 'name="NCSRF" value="([^"]*)"'
        if (-not $csrfMatch) {
            throw "Could not extract CSRF token from login page"
        }
        
        $csrfToken = $csrfMatch.Matches[0].Groups[1].Value
        Write-Verbose "Extracted CSRF token: $($csrfToken.Substring(0, 20))..."
        
        # Step 3: Prepare login data with CSRF token
        $loginData = @{
            Username = $Credential.UserName
            Password = $Credential.GetNetworkCredential().Password
            NCSRF = $csrfToken
        }
        
        # Step 4: Authenticate using the correct endpoint
        $loginUrl = "https://${ServerName}:${Port}/form/authenticate"
        Write-Verbose "Authenticating to: $loginUrl"
        
        $loginResponse = Invoke-WebRequest -Uri $loginUrl -Method POST -Body $loginData -WebSession $newSession -TimeoutSec 30
        
        if ($loginResponse.StatusCode -eq 200) {
            # Store session information
            $script:ModuleConfig.Session = $newSession
            $script:ModuleConfig.ServerName = $ServerName
            $script:ModuleConfig.Port = $Port
            $script:ModuleConfig.BaseUrl = "https://${ServerName}:${Port}/api"
            $script:ModuleConfig.Connected = $true
            $script:ModuleConfig.ConnectedAt = Get-Date
            
            # Also set global variables for backward compatibility
            $global:session = $newSession
            $global:servername = $ServerName
            
            Write-Host "Successfully connected to ProfileUnity server: $ServerName" -ForegroundColor Green
            return [PSCustomObject]@{
                ServerName = $ServerName
                Port = $Port
                Connected = $true
                AuthenticationTime = Get-Date
                CSRFToken = $csrfToken
            }
        }
        
        throw "Authentication failed with status code: $($loginResponse.StatusCode)"
    }
    catch {
        Write-Error "Connection failed: $($_.Exception.Message)"
        $script:ModuleConfig.Connected = $false
        throw
    }
}

function Get-ProfileUnityCredential {
    <#
    .SYNOPSIS
        Gets credentials for ProfileUnity authentication.
    
    .DESCRIPTION
        Internal function to handle credential collection for authentication.
    
    .PARAMETER Username
        Username (if not provided, will prompt)
    
    .PARAMETER Password
        Password (if not provided, will prompt securely)
    
    .EXAMPLE
        Get-ProfileUnityCredential -Username "admin" -Password "password"
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

function Test-ProfileUnityConnection {
    <#
    .SYNOPSIS
        Tests the connection to ProfileUnity server.
    
    .DESCRIPTION
        Verifies that the connection to ProfileUnity server is active.
    
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
            # Try to call the server/user endpoint to verify authentication
            $headers = @{
                'Accept' = 'application/json'
                'X-Requested-With' = 'XMLHttpRequest'
            }
            
            $testUrl = "https://${serverName}:8000/api/server/user?&_search=false&nd=$(Get-Date -UFormat %s)000&rows=1&page=1"
            
            $session = if ($script:ModuleConfig.Session) { 
                $script:ModuleConfig.Session 
            } else { 
                $global:session 
            }
            
            $response = Invoke-WebRequest -Uri $testUrl -Headers $headers -WebSession $session -ErrorAction Stop
            
            if ($response.StatusCode -eq 200 -and $response.Content -like '*"Type":"success"*') {
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

function Assert-ProfileUnityConnection {
    <#
    .SYNOPSIS
        Asserts that connection to ProfileUnity server is active.
    
    .DESCRIPTION
        Throws an error if no active connection exists.
    
    .EXAMPLE
        Assert-ProfileUnityConnection
    #>
    if (-not (($script:ModuleConfig.Session -and $script:ModuleConfig.ServerName) -or 
             ($global:session -and $global:servername))) {
        throw "No active connection to ProfileUnity server. Use Connect-ProfileUnityServer first."
    }
}

function Invoke-ProfileUnityApi {
    <#
    .SYNOPSIS
        Invokes a ProfileUnity API endpoint with proper authentication headers.
    
    .DESCRIPTION
        Wrapper function for making API calls to the ProfileUnity server.
        Handles authentication, JSON conversion, and error handling.
        Uses the same headers that work for API calls.
    
    .PARAMETER Endpoint
        The API endpoint (without /api/ prefix)
    
    .PARAMETER Method
        HTTP method (GET, POST, DELETE, etc.)
    
    .PARAMETER Body
        Request body (will be converted to JSON if not string)
    
    .PARAMETER OutFile
        File path to save response content
    
    .PARAMETER AdditionalHeaders
        Additional headers to include
    
    .EXAMPLE
        Invoke-ProfileUnityApi -Endpoint "server/user" -Method GET
        
    .EXAMPLE
        Invoke-ProfileUnityApi -Endpoint "configuration" -Method POST -Body $configObject
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method = 'GET',
        
        [object]$Body,
        
        [string]$OutFile,
        
        [hashtable]$AdditionalHeaders = @{}
    )
    
    # Ensure connection
    Assert-ProfileUnityConnection
    
    # Ensure we have a valid BaseUrl
    if (-not $script:ModuleConfig.BaseUrl) {
        $serverName = if ($script:ModuleConfig.ServerName) { 
            $script:ModuleConfig.ServerName 
        } else { 
            $global:servername 
        }
        $port = if ($script:ModuleConfig.Port) { 
            $script:ModuleConfig.Port 
        } else { 
            8000 
        }
        $script:ModuleConfig.BaseUrl = "https://${serverName}:${port}/api"
    }
    
    # Clean up endpoint
    $Endpoint = $Endpoint.TrimStart('/')
    
    # Set standard headers that work with ProfileUnity API
    $headers = @{
        'Accept' = 'application/json'
        'X-Requested-With' = 'XMLHttpRequest'
    }
    
    # Add any additional headers
    foreach ($key in $AdditionalHeaders.Keys) {
        $headers[$key] = $AdditionalHeaders[$key]
    }
    
    # Build request parameters
    $params = @{
        Uri = "$($script:ModuleConfig.BaseUrl)/$Endpoint"
        Method = $Method
        WebSession = if ($script:ModuleConfig.Session) { 
            $script:ModuleConfig.Session 
        } else { 
            $global:session 
        }
        Headers = $headers
        ErrorAction = 'Stop'
    }
    
    # Add body if provided
    if ($Body) {
        if ($Body -is [string]) {
            $params.Body = $Body
        }
        else {
            $params.Body = $Body | ConvertTo-Json -Depth 10 -Compress
        }
        $params.ContentType = 'application/json'
    }
    
    # Add output file if specified
    if ($OutFile) {
        $params.OutFile = $OutFile
    }
    
    Write-Verbose "$Method $($params.Uri)"
    
    try {
        # Use Invoke-WebRequest to get full response, then parse content
        $response = Invoke-WebRequest @params
        
        # Try to parse as JSON if it looks like JSON
        if ($response.Content -and $response.Content.TrimStart().StartsWith('{')) {
            try {
                return $response.Content | ConvertFrom-Json
            }
            catch {
                # If JSON parsing fails, return raw content
                return $response.Content
            }
        }
        
        return $response.Content
    }
    catch {
        Write-Verbose "API Error: $($_.Exception.Message)"
        
        # If we get authentication errors, suggest reconnecting
        if ($_.Exception.Response.StatusCode -eq 'Unauthorized' -or 
            $_.Exception.Response.StatusCode -eq 'Forbidden') {
            Write-Warning "Authentication may have expired. Try running Connect-ProfileUnityServer again."
        }
        
        throw
    }
}

function Set-TrustAllCertsPolicy {
    <#
    .SYNOPSIS
        Sets certificate policy to trust all certificates.
    
    .DESCRIPTION
        Disables SSL certificate validation for testing purposes.
    
    .EXAMPLE
        Set-TrustAllCertsPolicy
    #>
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class TrustAllCertsPolicy : ICertificatePolicy {
                public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
                    return true;
                }
            }
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    }
}

function Save-ProfileUnityItem {
    <#
    .SYNOPSIS
        Universal save function for ProfileUnity items.
    
    .DESCRIPTION
        Saves any ProfileUnity item type using the working pattern from single file PSM1.
    
    .PARAMETER ItemType
        Type of item to save (configuration, filter, portability, flexapppackage)
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Save-ProfileUnityItem -ItemType configuration -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('configuration', 'filter', 'portability', 'flexapppackage')]
        [string]$ItemType,
        
        [switch]$Force
    )
    
    $currentKey = switch ($ItemType) {
        'configuration' { 'Config' }
        'filter' { 'Filter' }
        'portability' { 'PortRule' }
        'flexapppackage' { 'FlexApp' }
    }
    
    $currentItem = $script:ModuleConfig.CurrentItems[$currentKey]
    
    # Also check global variables for backward compatibility
    if (-not $currentItem) {
        $currentItem = switch ($ItemType) {
            'configuration' { $global:CurrentConfig }
            'filter' { $global:CurrentFilter }
            'portability' { $global:CurrentPortRule }
            'flexapppackage' { $global:CurrentFlexapp }
        }
    }
    
    if (-not $currentItem) {
        throw "No $ItemType loaded for editing. Use Edit-ProU$currentKey first."
    }
    
    # Use standard PowerShell confirmation pattern
    # -Force bypasses confirmation, or user can use -Confirm:$false
    if ($Force -or $PSCmdlet.ShouldProcess("$ItemType on ProfileUnity server", "Save")) {
        try {
            Invoke-ProfileUnityApi -Endpoint $ItemType -Method POST -Body $currentItem
            Write-Host "$ItemType saved successfully" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to save ${ItemType}: $_"
            throw
        }
    }
    else {
        Write-Host "Save cancelled" -ForegroundColor Yellow
    }
}

function Get-ProfileUnityItem {
    <#
    .SYNOPSIS
        Universal get function for ProfileUnity items.
    
    .DESCRIPTION
        Retrieves ProfileUnity items with consistent API response handling.
    
    .PARAMETER ItemType
        Type of item to retrieve
    
    .PARAMETER Name
        Optional name filter
    
    .PARAMETER QueryParameters
        Additional query parameters as hashtable
    
    .EXAMPLE
        Get-ProfileUnityItem -ItemType configuration
        
    .EXAMPLE
        Get-ProfileUnityItem -ItemType "server/user" -QueryParameters @{rows=10; page=1}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ItemType,
        
        [string]$Name,
        
        [hashtable]$QueryParameters = @{}
    )
    
    try {
        # Build query string if parameters provided
        $queryString = ""
        if ($QueryParameters.Count -gt 0) {
            $queryParts = @()
            foreach ($key in $QueryParameters.Keys) {
                $queryParts += "$key=$($QueryParameters[$key])"
            }
            $queryString = "?" + ($queryParts -join "&")
        }
        
        $endpoint = $ItemType + $queryString
        $response = Invoke-ProfileUnityApi -Endpoint $endpoint
        
        # Handle different response formats consistently
        $items = if ($response.Tag.Rows) { 
            $response.Tag.Rows 
        } elseif ($response.tag) { 
            $response.tag 
        } elseif ($response) { 
            $response 
        } else { 
            @() 
        }
        
        if ($Name) {
            return $items | Where-Object { $_.name -like "*$Name*" }
        }
        return $items
    }
    catch {
        Write-Error "Failed to get $ItemType items: $_"
        throw
    }
}

function Edit-ProfileUnityItem {
    <#
    .SYNOPSIS
        Universal edit function for ProfileUnity items.
    
    .DESCRIPTION
        Loads ProfileUnity items for editing with consistent handling.
    
    .PARAMETER ItemType
        Type of item to edit
    
    .PARAMETER Name
        Name of the item to edit
    
    .PARAMETER Quiet
        Suppress confirmation messages
    
    .EXAMPLE
        Edit-ProfileUnityItem -ItemType configuration -Name "Test Config"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('configuration', 'filter', 'portability', 'flexapppackage')]
        [string]$ItemType,
        
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Quiet
    )
    
    try {
        $items = Get-ProfileUnityItem -ItemType $ItemType
        $item = $items | Where-Object { $_.name -eq $Name }
        
        if (-not $item) {
            throw "$ItemType '$Name' not found"
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "$ItemType/$($item.id)"
        $itemData = $response.tag
        
        # Store in appropriate current item AND global variable for backward compatibility
        $currentKey = switch ($ItemType) {
            'configuration' { 'Config' }
            'filter' { 'Filter' }
            'portability' { 'PortRule' }
            'flexapppackage' { 'FlexApp' }
        }
        
        $script:ModuleConfig.CurrentItems[$currentKey] = $itemData
        
        # Also set global variables for backward compatibility
        switch ($ItemType) {
            'configuration' { $global:CurrentConfig = $itemData }
            'filter' { $global:CurrentFilter = $itemData }
            'portability' { $global:CurrentPortRule = $itemData }
            'flexapppackage' { $global:CurrentFlexapp = $itemData }
        }
        
        if (-not $Quiet) {
            Write-Host "$Name loaded for editing" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to edit $ItemType '$Name': $_"
        throw
    }
}

# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
# Export-ModuleMember removed to prevent conflicts when dot-sourcing