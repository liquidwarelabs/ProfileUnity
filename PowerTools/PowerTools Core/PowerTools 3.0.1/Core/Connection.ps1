# Connection.ps1 - ProfileUnity Connection Management and API Wrapper

function Invoke-ProfileUnityApi {
    <#
    .SYNOPSIS
        Invokes a ProfileUnity API endpoint.
    
    .DESCRIPTION
        Wrapper function for making API calls to the ProfileUnity server.
        Handles authentication, JSON conversion, and error handling.
    
    .PARAMETER Endpoint
        The API endpoint (without /api/ prefix)
    
    .PARAMETER Method
        HTTP method (GET, POST, DELETE, etc.)
    
    .PARAMETER Body
        Request body (will be converted to JSON if not string)
    
    .PARAMETER ContentType
        Content type for the request
    
    .PARAMETER OutFile
        File path to save response content
    
    .EXAMPLE
        Invoke-ProfileUnityApi -Endpoint "configuration" -Method GET
        
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
        
        [string]$ContentType = 'application/json',
        
        [string]$OutFile,
        
        [hashtable]$Headers = @{},
        
        [switch]$RawResponse
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
    
    # Build request parameters
    $params = @{
        Uri = "$($script:ModuleConfig.BaseUrl)/$Endpoint"
        Method = $Method
        WebSession = if ($script:ModuleConfig.Session) { 
            $script:ModuleConfig.Session 
        } else { 
            $global:session 
        }
        Headers = $Headers
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
        $params.ContentType = $ContentType
    }
    
    # Add output file if specified
    if ($OutFile) {
        $params.OutFile = $OutFile
    }
    
    try {
        Write-Verbose "API Call: $Method $($params.Uri)"
        
        if ($RawResponse) {
            return Invoke-WebRequest @params
        }
        else {
            return Invoke-RestMethod @params
        }
    }
    catch {
        $errorMessage = "API call failed: $($_.Exception.Message)"
        
        # Try to extract more detailed error information
        if ($_.Exception.Response) {
            try {
                $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                $reader.Close()
                
                if ($responseBody) {
                    $errorMessage += "`nResponse: $responseBody"
                }
            }
            catch {
                # Ignore errors reading response
            }
        }
        
        Write-Error $errorMessage
        throw
    }
}

function Assert-ProfileUnityConnection {
    <#
    .SYNOPSIS
        Ensures an active ProfileUnity connection exists.
    
    .DESCRIPTION
        Internal function that throws an error if no connection is established.
    #>
    [CmdletBinding()]
    param()
    
    if (-not (Test-ProfileUnityConnection)) {
        throw "Not connected to ProfileUnity server. Please run Connect-ProfileUnityServer first."
    }
    
    # Ensure both storage methods have the session info for backward compatibility
    if ($global:session -and -not $script:ModuleConfig.Session) {
        $script:ModuleConfig.Session = $global:session
        $script:ModuleConfig.ServerName = $global:servername
        $script:ModuleConfig.BaseUrl = "https://${global:servername}:8000/api"
        $script:ModuleConfig.Connected = $true
    }
}

function Get-ProfileUnityApiEndpoints {
    <#
    .SYNOPSIS
        Gets available API endpoints from the ProfileUnity server.
    
    .DESCRIPTION
        Retrieves a list of available API endpoints for discovery purposes.
    
    .EXAMPLE
        Get-ProfileUnityApiEndpoints
    #>
    [CmdletBinding()]
    param()
    
    try {
        # This is a hypothetical endpoint - adjust based on actual API
        $endpoints = Invoke-ProfileUnityApi -Endpoint "enum" -Method GET
        
        return $endpoints | ForEach-Object {
            [PSCustomObject]@{
                Endpoint = $_
                Method = 'GET'  # Default, would need more info
                Description = $null
            }
        }
    }
    catch {
        Write-Warning "Could not retrieve API endpoints: $_"
        return $null
    }
}

function Invoke-ProfileUnityApiRaw {
    <#
    .SYNOPSIS
        Invokes a ProfileUnity API endpoint and returns raw response.
    
    .DESCRIPTION
        Similar to Invoke-ProfileUnityApi but returns the raw WebResponse object.
        Useful for debugging or when you need response headers/status codes.
    
    .PARAMETER Endpoint
        The API endpoint
    
    .PARAMETER Method
        HTTP method
    
    .PARAMETER Body
        Request body
    
    .EXAMPLE
        $response = Invoke-ProfileUnityApiRaw -Endpoint "configuration" -Method GET
        $response.StatusCode
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method = 'GET',
        
        [object]$Body,
        
        [hashtable]$Headers = @{}
    )
    
    return Invoke-ProfileUnityApi -Endpoint $Endpoint -Method $Method -Body $Body -Headers $Headers -RawResponse
}

function Wait-ProfileUnityTask {
    <#
    .SYNOPSIS
        Waits for a ProfileUnity task to complete.
    
    .DESCRIPTION
        Polls a task endpoint until the task completes or times out.
    
    .PARAMETER TaskId
        The task ID to monitor
    
    .PARAMETER TimeoutSeconds
        Maximum time to wait (default: 300 seconds)
    
    .PARAMETER PollingInterval
        How often to check status (default: 5 seconds)
    
    .EXAMPLE
        Wait-ProfileUnityTask -TaskId "12345" -TimeoutSeconds 600
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskId,
        
        [int]$TimeoutSeconds = 300,
        
        [int]$PollingInterval = 5
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    Write-Host "Waiting for task $TaskId to complete..." -ForegroundColor Yellow
    
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $task = Invoke-ProfileUnityApi -Endpoint "task/$TaskId" -Method GET
            
            if ($task.Status -eq 'Completed') {
                Write-Host "Task completed successfully" -ForegroundColor Green
                return $task
            }
            elseif ($task.Status -eq 'Failed' -or $task.Status -eq 'Cancelled') {
                throw "Task $TaskId failed with status: $($task.Status)"
            }
            
            Write-Verbose "Task status: $($task.Status) - Elapsed: $($stopwatch.Elapsed.TotalSeconds)s"
            Start-Sleep -Seconds $PollingInterval
        }
        catch {
            throw "Error checking task status: $_"
        }
    }
    
    throw "Task $TaskId timed out after $TimeoutSeconds seconds"
}

function Test-ProfileUnityApiEndpoint {
    <#
    .SYNOPSIS
        Tests if an API endpoint is accessible.
    
    .DESCRIPTION
        Performs a test call to verify an endpoint exists and is accessible.
    
    .PARAMETER Endpoint
        The endpoint to test
    
    .EXAMPLE
        Test-ProfileUnityApiEndpoint -Endpoint "configuration"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint
    )
    
    try {
        $null = Invoke-ProfileUnityApi -Endpoint $Endpoint -Method GET -ErrorAction Stop
        return $true
    }
    catch {
        Write-Verbose "Endpoint test failed: $_"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Invoke-ProfileUnityApi',
    'Invoke-ProfileUnityApiRaw',
    'Get-ProfileUnityApiEndpoints',
    'Wait-ProfileUnityTask',
    'Test-ProfileUnityApiEndpoint'
)