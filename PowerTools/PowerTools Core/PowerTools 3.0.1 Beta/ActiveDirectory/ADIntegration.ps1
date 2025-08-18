# ADIntegration.ps1 - ProfileUnity Active Directory Integration Functions

function Get-ProUADDomains {
    <#
    .SYNOPSIS
        Gets Active Directory domains.
    
    .DESCRIPTION
        Retrieves list of available AD domains for ProfileUnity integration.
    
    .EXAMPLE
        Get-ProUADDomains
    #>
    [CmdletBinding()]
    param()
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "ad/domains"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.name
                    NetBiosName = $_.netBiosName
                    DistinguishedName = $_.distinguishedName
                    DomainMode = $_.domainMode
                    ForestMode = $_.forestMode
                    PDCEmulator = $_.pdcEmulator
                    IsConnected = $_.isConnected
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get AD domains: $_"
        throw
    }
}

function Get-ProUADDomainControllers {
    <#
    .SYNOPSIS
        Gets Active Directory domain controllers.
    
    .DESCRIPTION
        Retrieves information about domain controllers in the environment.
    
    .EXAMPLE
        Get-ProUADDomainControllers
    #>
    [CmdletBinding()]
    param()
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "ad/domaincontroller"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.name
                    Domain = $_.domain
                    Site = $_.site
                    IPAddress = $_.ipAddress
                    OperatingSystem = $_.operatingSystem
                    Roles = $_.roles
                    IsGlobalCatalog = $_.isGlobalCatalog
                    IsReachable = $_.isReachable
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get AD domain controllers: $_"
        throw
    }
}

function Get-ProUADUsers {
    <#
    .SYNOPSIS
        Gets Active Directory users.
    
    .DESCRIPTION
        Retrieves AD user information with filtering options.
    
    .PARAMETER Name
        User name filter (supports wildcards)
    
    .PARAMETER Domain
        Specific domain to search
    
    .PARAMETER OU
        Organizational Unit to search
    
    .PARAMETER Enabled
        Filter by enabled/disabled status
    
    .PARAMETER MaxResults
        Maximum number of results to return
    
    .EXAMPLE
        Get-ProUADUsers -Name "john*" -Enabled $true
        
    .EXAMPLE
        Get-ProUADUsers -OU "OU=Users,DC=domain,DC=com" -MaxResults 100
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Domain,
        [string]$OU,
        [bool]$Enabled,
        [int]$MaxResults = 1000
    )
    
    try {
        $queryParams = @{}
        
        if ($Name) { $queryParams.name = $Name }
        if ($Domain) { $queryParams.domain = $Domain }
        if ($OU) { $queryParams.ou = $OU }
        if ($PSBoundParameters.ContainsKey('Enabled')) { $queryParams.enabled = $Enabled }
        if ($MaxResults) { $queryParams.maxResults = $MaxResults }
        
        $queryString = if ($queryParams.Count -gt 0) {
            "?" + (($queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&")
        } else { "" }
        
        $response = Invoke-ProfileUnityApi -Endpoint "ad/user$queryString"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    SamAccountName = $_.samAccountName
                    DisplayName = $_.displayName
                    UserPrincipalName = $_.userPrincipalName
                    DistinguishedName = $_.distinguishedName
                    Domain = $_.domain
                    Enabled = $_.enabled
                    LastLogon = $_.lastLogon
                    PasswordLastSet = $_.passwordLastSet
                    Email = $_.email
                    Department = $_.department
                    Title = $_.title
                    Manager = $_.manager
                    Groups = $_.groups
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get AD users: $_"
        throw
    }
}

function Get-ProUADGroups {
    <#
    .SYNOPSIS
        Gets Active Directory groups.
    
    .DESCRIPTION
        Retrieves AD group information with filtering options.
    
    .PARAMETER Name
        Group name filter (supports wildcards)
    
    .PARAMETER Domain
        Specific domain to search
    
    .PARAMETER OU
        Organizational Unit to search
    
    .PARAMETER Type
        Group type filter (Security, Distribution)
    
    .PARAMETER Scope
        Group scope filter (Global, Universal, DomainLocal)
    
    .PARAMETER MaxResults
        Maximum number of results to return
    
    .EXAMPLE
        Get-ProUADGroups -Name "*admin*" -Type Security
        
    .EXAMPLE
        Get-ProUADGroups -OU "OU=Groups,DC=domain,DC=com" -Scope Global
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Domain,
        [string]$OU,
        [ValidateSet('Security', 'Distribution')]
        [string]$Type,
        [ValidateSet('Global', 'Universal', 'DomainLocal')]
        [string]$Scope,
        [int]$MaxResults = 1000
    )
    
    try {
        $queryParams = @{}
        
        if ($Name) { $queryParams.name = $Name }
        if ($Domain) { $queryParams.domain = $Domain }
        if ($OU) { $queryParams.ou = $OU }
        if ($Type) { $queryParams.type = $Type }
        if ($Scope) { $queryParams.scope = $Scope }
        if ($MaxResults) { $queryParams.maxResults = $MaxResults }
        
        $queryString = if ($queryParams.Count -gt 0) {
            "?" + (($queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&")
        } else { "" }
        
        $response = Invoke-ProfileUnityApi -Endpoint "ad/group$queryString"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.name
                    SamAccountName = $_.samAccountName
                    DistinguishedName = $_.distinguishedName
                    Domain = $_.domain
                    GroupType = $_.groupType
                    GroupScope = $_.groupScope
                    Description = $_.description
                    MemberCount = $_.memberCount
                    Members = $_.members
                    ManagedBy = $_.managedBy
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get AD groups: $_"
        throw
    }
}

function Get-ProUADComputers {
    <#
    .SYNOPSIS
        Gets Active Directory computers.
    
    .DESCRIPTION
        Retrieves AD computer information with filtering options.
    
    .PARAMETER Name
        Computer name filter (supports wildcards)
    
    .PARAMETER Domain
        Specific domain to search
    
    .PARAMETER OU
        Organizational Unit to search
    
    .PARAMETER OperatingSystem
        Operating system filter
    
    .PARAMETER Enabled
        Filter by enabled/disabled status
    
    .PARAMETER MaxResults
        Maximum number of results to return
    
    .EXAMPLE
        Get-ProUADComputers -Name "WS-*" -Enabled $true
        
    .EXAMPLE
        Get-ProUADComputers -OperatingSystem "*Windows 10*" -MaxResults 500
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Domain,
        [string]$OU,
        [string]$OperatingSystem,
        [bool]$Enabled,
        [int]$MaxResults = 1000
    )
    
    try {
        $queryParams = @{}
        
        if ($Name) { $queryParams.name = $Name }
        if ($Domain) { $queryParams.domain = $Domain }
        if ($OU) { $queryParams.ou = $OU }
        if ($OperatingSystem) { $queryParams.operatingSystem = $OperatingSystem }
        if ($PSBoundParameters.ContainsKey('Enabled')) { $queryParams.enabled = $Enabled }
        if ($MaxResults) { $queryParams.maxResults = $MaxResults }
        
        $queryString = if ($queryParams.Count -gt 0) {
            "?" + (($queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&")
        } else { "" }
        
        $response = Invoke-ProfileUnityApi -Endpoint "ad/computer$queryString"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.name
                    SamAccountName = $_.samAccountName
                    DistinguishedName = $_.distinguishedName
                    Domain = $_.domain
                    Enabled = $_.enabled
                    OperatingSystem = $_.operatingSystem
                    OperatingSystemVersion = $_.operatingSystemVersion
                    LastLogon = $_.lastLogon
                    IPAddress = $_.ipAddress
                    Location = $_.location
                    Description = $_.description
                    ManagedBy = $_.managedBy
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get AD computers: $_"
        throw
    }
}

function Get-ProUADOrganizationalUnits {
    <#
    .SYNOPSIS
        Gets Active Directory organizational units.
    
    .DESCRIPTION
        Retrieves AD OU structure and information.
    
    .PARAMETER Name
        OU name filter (supports wildcards)
    
    .PARAMETER Domain
        Specific domain to search
    
    .PARAMETER ParentOU
        Parent OU to search under
    
    .EXAMPLE
        Get-ProUADOrganizationalUnits -Name "*Users*"
        
    .EXAMPLE
        Get-ProUADOrganizationalUnits -Domain "domain.com" -ParentOU "OU=Company,DC=domain,DC=com"
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Domain,
        [string]$ParentOU
    )
    
    try {
        $queryParams = @{}
        
        if ($Name) { $queryParams.name = $Name }
        if ($Domain) { $queryParams.domain = $Domain }
        if ($ParentOU) { $queryParams.parentOU = $ParentOU }
        
        $queryString = if ($queryParams.Count -gt 0) {
            "?" + (($queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&")
        } else { "" }
        
        $response = Invoke-ProfileUnityApi -Endpoint "ad/ou$queryString"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.name
                    DistinguishedName = $_.distinguishedName
                    Domain = $_.domain
                    Description = $_.description
                    ParentOU = $_.parentOU
                    ChildOUCount = $_.childOUCount
                    UserCount = $_.userCount
                    ComputerCount = $_.computerCount
                    GroupCount = $_.groupCount
                    ManagedBy = $_.managedBy
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get AD organizational units: $_"
        throw
    }
}

function Test-ProUADConnectivity {
    <#
    .SYNOPSIS
        Tests Active Directory connectivity.
    
    .DESCRIPTION
        Tests connection to Active Directory domains and domain controllers.
    
    .PARAMETER Domain
        Specific domain to test
    
    .EXAMPLE
        Test-ProUADConnectivity
        
    .EXAMPLE
        Test-ProUADConnectivity -Domain "contoso.com"
    #>
    [CmdletBinding()]
    param(
        [string]$Domain
    )
    
    try {
        Write-Host "Testing Active Directory connectivity..." -ForegroundColor Yellow
        
        $issues = @()
        $warnings = @()
        $info = @{}
        
        # Test domain connectivity
        try {
            $domains = Get-ProUADDomains
            if ($Domain) {
                $domains = $domains | Where-Object { $_.Name -eq $Domain }
                if (-not $domains) {
                    $issues += "Specified domain '$Domain' not found"
                    return
                }
            }
            
            $info.DomainCount = $domains.Count
            $connectedDomains = $domains | Where-Object { $_.IsConnected }
            $info.ConnectedDomains = $connectedDomains.Count
            
            if ($connectedDomains.Count -eq 0) {
                $issues += "No domains are connected"
            } elseif ($connectedDomains.Count -lt $domains.Count) {
                $warnings += "Some domains are not connected: $($domains.Count - $connectedDomains.Count)"
            }
            
            foreach ($dom in $domains) {
                $status = if ($dom.IsConnected) { "Connected" } else { "Disconnected" }
                Write-Host "  Domain $($dom.Name): $status" -ForegroundColor $(if ($dom.IsConnected) { "Green" } else { "Red" })
            }
        }
        catch {
            $issues += "Cannot retrieve domain information: $_"
        }
        
        # Test domain controllers
        try {
            $dcs = Get-ProUADDomainControllers
            if ($dcs) {
                $info.DomainControllerCount = $dcs.Count
                $reachableDCs = $dcs | Where-Object { $_.IsReachable }
                $info.ReachableDCs = $reachableDCs.Count
                
                if ($reachableDCs.Count -eq 0) {
                    $issues += "No domain controllers are reachable"
                } elseif ($reachableDCs.Count -lt $dcs.Count) {
                    $warnings += "Some domain controllers are unreachable: $($dcs.Count - $reachableDCs.Count)"
                }
                
                Write-Host "  Reachable DCs: $($reachableDCs.Count)/$($dcs.Count)" -ForegroundColor Green
            } else {
                $warnings += "No domain controllers found"
            }
        }
        catch {
            $warnings += "Cannot retrieve domain controller information"
        }
        
        # Test basic AD queries
        try {
            $testUsers = Get-ProUADUsers -MaxResults 1
            if ($testUsers) {
                Write-Host "  User query test: OK" -ForegroundColor Green
            } else {
                $warnings += "User query returned no results"
            }
        }
        catch {
            $issues += "Cannot query AD users: $_"
        }
        
        try {
            $testGroups = Get-ProUADGroups -MaxResults 1
            if ($testGroups) {
                Write-Host "  Group query test: OK" -ForegroundColor Green
            } else {
                $warnings += "Group query returned no results"
            }
        }
        catch {
            $issues += "Cannot query AD groups: $_"
        }
        
        # Display results
        Write-Host "`nActive Directory Connectivity Test Results:" -ForegroundColor Cyan
        
        if ($info.Count -gt 0) {
            Write-Host "AD Information:" -ForegroundColor Gray
            $info.GetEnumerator() | ForEach-Object {
                Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
            }
        }
        
        if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
            Write-Host "  AD connectivity: OK" -ForegroundColor Green
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
            ADInfo = $info
            Issues = $issues
            Warnings = $warnings
            IsHealthy = $issues.Count -eq 0
        }
    }
    catch {
        Write-Error "Failed to test AD connectivity: $_"
        throw
    }
}

function Search-ProUAD {
    <#
    .SYNOPSIS
        Searches Active Directory objects.
    
    .DESCRIPTION
        Performs a general search across AD users, groups, and computers.
    
    .PARAMETER SearchTerm
        Search term to look for
    
    .PARAMETER ObjectType
        Type of AD objects to search
    
    .PARAMETER Domain
        Specific domain to search
    
    .PARAMETER MaxResults
        Maximum number of results per object type
    
    .EXAMPLE
        Search-ProUAD -SearchTerm "admin" -ObjectType All
        
    .EXAMPLE
        Search-ProUAD -SearchTerm "john.doe" -ObjectType Users -Domain "contoso.com"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SearchTerm,
        
        [ValidateSet('Users', 'Groups', 'Computers', 'All')]
        [string]$ObjectType = 'All',
        
        [string]$Domain,
        
        [int]$MaxResults = 100
    )
    
    try {
        $results = @{}
        
        if ($ObjectType -in @('Users', 'All')) {
            Write-Verbose "Searching users..."
            try {
                $userParams = @{
                    Name = "*$SearchTerm*"
                    MaxResults = $MaxResults
                }
                if ($Domain) { $userParams.Domain = $Domain }
                
                $users = Get-ProUADUsers @userParams
                if ($users) {
                    $results.Users = $users
                    Write-Host "Found $($users.Count) users matching '$SearchTerm'" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "User search failed: $_"
            }
        }
        
        if ($ObjectType -in @('Groups', 'All')) {
            Write-Verbose "Searching groups..."
            try {
                $groupParams = @{
                    Name = "*$SearchTerm*"
                    MaxResults = $MaxResults
                }
                if ($Domain) { $groupParams.Domain = $Domain }
                
                $groups = Get-ProUADGroups @groupParams
                if ($groups) {
                    $results.Groups = $groups
                    Write-Host "Found $($groups.Count) groups matching '$SearchTerm'" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "Group search failed: $_"
            }
        }
        
        if ($ObjectType -in @('Computers', 'All')) {
            Write-Verbose "Searching computers..."
            try {
                $computerParams = @{
                    Name = "*$SearchTerm*"
                    MaxResults = $MaxResults
                }
                if ($Domain) { $computerParams.Domain = $Domain }
                
                $computers = Get-ProUADComputers @computerParams
                if ($computers) {
                    $results.Computers = $computers
                    Write-Host "Found $($computers.Count) computers matching '$SearchTerm'" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "Computer search failed: $_"
            }
        }
        
        if ($results.Count -eq 0) {
            Write-Host "No objects found matching '$SearchTerm'" -ForegroundColor Yellow
        }
        
        return $results
    }
    catch {
        Write-Error "Failed to search Active Directory: $_"
        throw
    }
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Get-ProUADDomains',
    'Get-ProUADDomainControllers',
    'Test-ProUADConnectivity',
    'Search-ProUAD'
)
#>




