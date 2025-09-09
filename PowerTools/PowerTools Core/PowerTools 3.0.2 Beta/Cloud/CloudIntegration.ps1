# Cloud\CloudIntegration.ps1 - ProfileUnity Cloud Integration Functions (Enhanced)

function Get-ProUCloudCredentials {
    <#
    .SYNOPSIS
        Gets ProfileUnity cloud service credentials.
    
    .DESCRIPTION
        Retrieves all configured cloud service credentials.
    
    .PARAMETER Name
        Optional name filter
    
    .EXAMPLE
        Get-ProUCloudCredentials
        
    .EXAMPLE
        Get-ProUCloudCredentials -Name "Azure*"
    #>
    [CmdletBinding()]
    param(
        [string]$Name
    )
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "cloud/credential"
        
        if ($response) {
            $credentials = $response | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_.id
                    Name = $_.name
                    Type = $_.credentialType
                    ClientId = $_.clientId
                    TenantId = $_.tenantId
                    Created = $_.created
                    LastUsed = $_.lastUsed
                    Status = $_.status
                }
            }
            
            if ($Name) {
                $credentials = $credentials | Where-Object { $_.Name -like $Name }
            }
            
            return $credentials
        }
    }
    catch {
        Write-Error "Failed to get cloud credentials: $_"
        throw
    }
}

function New-ProUCloudCredential {
    <#
    .SYNOPSIS
        Creates new cloud service credentials.
    
    .DESCRIPTION
        Adds new credentials for cloud service integration.
    
    .PARAMETER Name
        Display name for the credentials
    
    .PARAMETER Type
        Credential type (Azure, AWS, etc.)
    
    .PARAMETER ClientId
        Client/Application ID
    
    .PARAMETER ClientSecret
        Client secret/key
    
    .PARAMETER TenantId
        Tenant ID (for Azure)
    
    .EXAMPLE
        New-ProUCloudCredential -Name "Azure Prod" -Type "Azure" -ClientId "abc123" -ClientSecret "secret" -TenantId "tenant123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [ValidateSet('Azure', 'AWS', 'GCP')]
        [string]$Type,
        
        [Parameter(Mandatory)]
        [string]$ClientId,
        
        [Parameter(Mandatory)]
        [string]$ClientSecret,
        
        [string]$TenantId
    )
    
    try {
        $body = @{
            name = $Name
            credentialType = $Type
            clientId = $ClientId
            clientSecret = $ClientSecret
        }
        
        if ($TenantId) {
            $body.tenantId = $TenantId
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "cloud/credential" -Method POST -Body $body
        
        if ($response) {
            Write-Host "Cloud credential created: $Name" -ForegroundColor Green
            return $response
        }
    }
    catch {
        Write-Error "Failed to create cloud credential: $_"
        throw
    }
}

function Copy-ProUCloudCredential {
    <#
    .SYNOPSIS
        Copies an existing cloud credential.
    
    .DESCRIPTION
        Creates a copy of an existing cloud credential with a new name.
    
    .PARAMETER Id
        ID of credential to copy
    
    .PARAMETER Name
        Name of credential to copy
    
    .PARAMETER NewName
        Name for the copied credential
    
    .EXAMPLE
        Copy-ProUCloudCredential -Id "12345" -NewName "Azure Test Copy"
        
    .EXAMPLE
        Copy-ProUCloudCredential -Name "Azure Production" -NewName "Azure Test Copy"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$NewName
    )
    
    try {
        # Resolve name to ID if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Resolving credential name '$Name' to ID..."
            $credential = Get-ProUCloudCredentials | Where-Object { $_.Name -eq $Name }
            
            if (-not $credential) {
                throw "Cloud credential '$Name' not found"
            }
            
            if ($credential -is [array] -and $credential.Count -gt 1) {
                throw "Multiple credentials found with name '$Name'. Use -Id parameter instead."
            }
            
            $Id = $credential.Id
            Write-Verbose "Resolved to ID: $Id"
        }
        
        $body = @{
            name = $NewName
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "cloud/credential/$Id/copy" -Method POST -Body $body
        
        if ($response) {
            Write-Host "Cloud credential copied: $NewName" -ForegroundColor Green
            return $response
        }
    }
    catch {
        Write-Error "Failed to copy cloud credential: $_"
        throw
    }
}

function Test-ProUCloudCredential {
    <#
    .SYNOPSIS
        Tests cloud service credentials.
    
    .DESCRIPTION
        Validates cloud service credentials and permissions.
    
    .PARAMETER Id
        ID of credential to test
    
    .PARAMETER Name
        Name of credential to test
    
    .EXAMPLE
        Test-ProUCloudCredential -Id "12345"
        
    .EXAMPLE
        Test-ProUCloudCredential -Name "Azure Production"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name
    )
    
    try {
        # Resolve name to ID if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Resolving credential name '$Name' to ID..."
            $credential = Get-ProUCloudCredentials | Where-Object { $_.Name -eq $Name }
            
            if (-not $credential) {
                throw "Cloud credential '$Name' not found"
            }
            
            if ($credential -is [array] -and $credential.Count -gt 1) {
                throw "Multiple credentials found with name '$Name'. Use -Id parameter instead."
            }
            
            $Id = $credential.Id
            Write-Verbose "Resolved to ID: $Id"
        }
        
        Write-Host "Testing cloud credential..." -ForegroundColor Yellow
        
        $response = Invoke-ProfileUnityApi -Endpoint "cloud/credential/$Id/test" -Method POST
        
        if ($response) {
            $success = $response.success
            $message = $response.message
            
            if ($success) {
                Write-Host "Credential test successful: $message" -ForegroundColor Green
            }
            else {
                Write-Warning "Credential test failed: $message"
            }
            
            return [PSCustomObject]@{
                Success = $success
                Message = $message
                Details = $response.details
            }
        }
    }
    catch {
        Write-Error "Failed to test cloud credential: $_"
        throw
    }
}

function Remove-ProUCloudCredential {
    <#
    .SYNOPSIS
        Removes a cloud credential.
    
    .DESCRIPTION
        Deletes a cloud service credential from ProfileUnity.
    
    .PARAMETER Id
        ID of credential to remove
    
    .PARAMETER Name
        Name of credential to remove
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Remove-ProUCloudCredential -Id "12345"
        
    .EXAMPLE
        Remove-ProUCloudCredential -Name "Azure Test" -Force
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,
        
        [switch]$Force
    )
    
    try {
        # Resolve name to ID if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Resolving credential name '$Name' to ID..."
            $credential = Get-ProUCloudCredentials | Where-Object { $_.Name -eq $Name }
            
            if (-not $credential) {
                throw "Cloud credential '$Name' not found"
            }
            
            if ($credential -is [array] -and $credential.Count -gt 1) {
                throw "Multiple credentials found with name '$Name'. Use -Id parameter instead."
            }
            
            $Id = $credential.Id
            $credentialName = $credential.Name
            Write-Verbose "Resolved to ID: $Id"
        }
        else {
            # Get name for confirmation
            $credential = Get-ProUCloudCredentials | Where-Object { $_.Id -eq $Id }
            $credentialName = if ($credential) { $credential.Name } else { "ID: $Id" }
        }
        
        if ($PSCmdlet.ShouldProcess($credentialName, "Remove cloud credential")) {
            if (-not $Force) {
                $confirm = Read-Host "Are you sure you want to remove credential '$credentialName'? (y/N)"
                if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                    Write-Host "Operation cancelled" -ForegroundColor Yellow
                    return
                }
            }
            
            $response = Invoke-ProfileUnityApi -Endpoint "cloud/credential/$Id" -Method DELETE
            
            Write-Host "Cloud credential removed: $credentialName" -ForegroundColor Green
            return $response
        }
    }
    catch {
        Write-Error "Failed to remove cloud credential: $_"
        throw
    }
}

# Azure-specific functions with enhanced parameter handling

function Get-ProUAzureGraph {
    <#
    .SYNOPSIS
        Queries Azure Graph API through ProfileUnity.
    
    .DESCRIPTION
        Executes Graph API queries using configured Azure credentials.
    
    .PARAMETER CredentialId
        Azure credential ID to use
    
    .PARAMETER CredentialName
        Azure credential name to use
    
    .PARAMETER Query
        Graph API query to execute
    
    .PARAMETER ApiVersion
        Graph API version (default: v1.0)
    
    .EXAMPLE
        Get-ProUAzureGraph -CredentialName "Azure Production" -Query "users"
        
    .EXAMPLE
        Get-ProUAzureGraph -CredentialId "12345" -Query "groups" -ApiVersion "beta"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$CredentialId,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$CredentialName,
        
        [Parameter(Mandatory)]
        [string]$Query,
        
        [string]$ApiVersion = 'v1.0'
    )
    
    try {
        # Resolve name to ID if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Resolving credential name '$CredentialName' to ID..."
            $credential = Get-ProUCloudCredentials | Where-Object { $_.Name -eq $CredentialName -and $_.Type -eq 'Azure' }
            
            if (-not $credential) {
                throw "Azure credential '$CredentialName' not found"
            }
            
            if ($credential -is [array] -and $credential.Count -gt 1) {
                throw "Multiple Azure credentials found with name '$CredentialName'. Use -CredentialId parameter instead."
            }
            
            $CredentialId = $credential.Id
            Write-Verbose "Resolved to ID: $CredentialId"
        }
        
        $body = @{
            credentialId = $CredentialId
            query = $Query
            apiVersion = $ApiVersion
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "cloud/azure/graph" -Method POST -Body $body
        
        if ($response) {
            return $response.data
        }
    }
    catch {
        Write-Error "Failed to query Azure Graph: $_"
        throw
    }
}

function Get-ProUAzureGroups {
    <#
    .SYNOPSIS
        Gets Azure AD groups.
    
    .DESCRIPTION
        Retrieves Azure AD groups using configured credentials.
    
    .PARAMETER CredentialId
        Azure credential ID to use
    
    .PARAMETER CredentialName
        Azure credential name to use
    
    .PARAMETER Filter
        OData filter expression
    
    .PARAMETER MaxResults
        Maximum number of results
    
    .EXAMPLE
        Get-ProUAzureGroups -CredentialName "Azure Production"
        
    .EXAMPLE
        Get-ProUAzureGroups -CredentialId "12345" -Filter "startswith(displayName,'Sales')" -MaxResults 50
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$CredentialId,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$CredentialName,
        
        [string]$Filter,
        
        [int]$MaxResults = 100
    )
    
    try {
        # Resolve name to ID if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Resolving credential name '$CredentialName' to ID..."
            $credential = Get-ProUCloudCredentials | Where-Object { $_.Name -eq $CredentialName -and $_.Type -eq 'Azure' }
            
            if (-not $credential) {
                throw "Azure credential '$CredentialName' not found"
            }
            
            if ($credential -is [array] -and $credential.Count -gt 1) {
                throw "Multiple Azure credentials found with name '$CredentialName'. Use -CredentialId parameter instead."
            }
            
            $CredentialId = $credential.Id
            Write-Verbose "Resolved to ID: $CredentialId"
        }
        
        # Build Graph query
        $query = "groups"
        $queryParams = @()
        
        if ($Filter) {
            $queryParams += "`$filter=$([System.Web.HttpUtility]::UrlEncode($Filter))"
        }
        
        if ($MaxResults) {
            $queryParams += "`$top=$MaxResults"
        }
        
        if ($queryParams.Count -gt 0) {
            $query += "?" + ($queryParams -join "&")
        }
        
        $groups = Get-ProUAzureGraph -CredentialId $CredentialId -Query $query
        
        if ($groups.value) {
            return $groups.value | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_.id
                    DisplayName = $_.displayName
                    MailNickname = $_.mailNickname
                    Description = $_.description
                    GroupType = $_.groupType
                    SecurityEnabled = $_.securityEnabled
                    MailEnabled = $_.mailEnabled
                    CreatedDateTime = $_.createdDateTime
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get Azure groups: $_"
        throw
    }
}

function Request-ProUAzureGraphToken {
    <#
    .SYNOPSIS
        Requests Azure Graph API token.
    
    .DESCRIPTION
        Obtains authentication tokens for Graph API using stored credentials.
    
    .PARAMETER CredentialId
        Azure credential ID to use
    
    .PARAMETER CredentialName
        Azure credential name to use
    
    .PARAMETER Scope
        Token scope (default: https://graph.microsoft.com/.default)
    
    .EXAMPLE
        Request-ProUAzureGraphToken -CredentialName "Azure Production"
        
    .EXAMPLE
        Request-ProUAzureGraphToken -CredentialId "12345" -Scope "https://graph.microsoft.com/User.Read"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$CredentialId,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$CredentialName,
        
        [string]$Scope = 'https://graph.microsoft.com/.default'
    )
    
    try {
        # Resolve name to ID if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Resolving credential name '$CredentialName' to ID..."
            $credential = Get-ProUCloudCredentials | Where-Object { $_.Name -eq $CredentialName -and $_.Type -eq 'Azure' }
            
            if (-not $credential) {
                throw "Azure credential '$CredentialName' not found"
            }
            
            if ($credential -is [array] -and $credential.Count -gt 1) {
                throw "Multiple Azure credentials found with name '$CredentialName'. Use -CredentialId parameter instead."
            }
            
            $CredentialId = $credential.Id
            Write-Verbose "Resolved to ID: $CredentialId"
        }
        
        $body = @{
            credentialId = $CredentialId
            scope = $Scope
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "cloud/azure/token" -Method POST -Body $body
        
        if ($response) {
            Write-Host "Azure Graph token obtained successfully" -ForegroundColor Green
            return [PSCustomObject]@{
                AccessToken = $response.accessToken
                TokenType = $response.tokenType
                ExpiresIn = $response.expiresIn
                ExpiresAt = (Get-Date).AddSeconds($response.expiresIn)
                Scope = $response.scope
            }
        }
    }
    catch {
        Write-Error "Failed to request Azure Graph token: $_"
        throw
    }
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Get-ProUCloudCredentials',
    'New-ProUCloudCredential',
    'Copy-ProUCloudCredential',
    'Remove-ProUCloudCredential',
    'Get-ProUAzureSubscriptions',
    'Get-ProUAzureResourceGroups',
    'Get-ProUAzureHostPools',
    'Get-ProUAzureLocations',
    'Test-ProUAzureDomain',
    'Get-ProUAzureSearchableDomains',
    'Sync-ProUAppAttachPackages')
#>




