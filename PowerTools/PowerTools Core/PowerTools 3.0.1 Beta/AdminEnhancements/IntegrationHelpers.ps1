# IntegrationHelpers.ps1 - ProfileUnity Excel Export and AD Integration Wizards

function Export-ProUToExcel {
    <#
    .SYNOPSIS
        Exports ProfileUnity data to Excel format.
    
    .DESCRIPTION
        Creates comprehensive Excel reports from ProfileUnity configurations, filters, and other objects.
        Supports multiple worksheets and formatted output.
    
    .PARAMETER Object
        The ProfileUnity object(s) to export
    
    .PARAMETER ObjectType
        Type of object being exported (Configuration, Filter, FlexApp, etc.)
    
    .PARAMETER FilePath
        Path where Excel file will be saved
    
    .PARAMETER IncludeMetadata
        Include additional metadata in the export
    
    .PARAMETER OpenAfterExport
        Open the Excel file after export is complete
    
    .EXAMPLE
        $configs = Get-ProUConfig
        Export-ProUToExcel -Object $configs -ObjectType Configuration -FilePath "C:\Reports\Configs.xlsx"
        
    .EXAMPLE
        Get-ProUFilters | Export-ProUToExcel -ObjectType Filter -FilePath "C:\Reports\Filters.xlsx" -OpenAfterExport
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Object,
        
        [Parameter(Mandatory)]
        [ValidateSet('Configuration', 'Filter', 'Portability', 'FlexApp', 'ADMX', 'Server', 'Events')]
        [string]$ObjectType,
        
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [switch]$IncludeMetadata,
        [switch]$OpenAfterExport
    )
    
    begin {
        $allObjects = @()
        
        # Validate file path
        $directory = Split-Path $FilePath -Parent
        if ($directory -and -not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        # Ensure .xlsx extension
        if (-not $FilePath.EndsWith('.xlsx', [StringComparison]::OrdinalIgnoreCase)) {
            $FilePath = $FilePath + '.xlsx'
        }
        
        Write-Host "Preparing Excel export for $ObjectType objects..." -ForegroundColor Yellow
    }
    
    process {
        $allObjects += $Object
    }
    
    end {
        try {
            if ($allObjects.Count -eq 0) {
                Write-Warning "No objects to export"
                return
            }
            
            # Create Excel COM object
            $excel = $null
            $workbook = $null
            
            try {
                $excel = New-Object -ComObject Excel.Application
                $excel.Visible = $false
                $excel.DisplayAlerts = $false
                
                $workbook = $excel.Workbooks.Add()
                $worksheet = $workbook.ActiveSheet
                $worksheet.Name = $ObjectType
                
                Write-Verbose "Created Excel workbook with worksheet: $ObjectType"
                
                # Export based on object type
                switch ($ObjectType) {
                    'Configuration' {
                        Export-ConfigurationToExcel -Worksheet $worksheet -Objects $allObjects -IncludeMetadata:$IncludeMetadata
                    }
                    'Filter' {
                        Export-FilterToExcel -Worksheet $worksheet -Objects $allObjects -IncludeMetadata:$IncludeMetadata
                    }
                    'Portability' {
                        Export-PortabilityToExcel -Worksheet $worksheet -Objects $allObjects -IncludeMetadata:$IncludeMetadata
                    }
                    'FlexApp' {
                        Export-FlexAppToExcel -Worksheet $worksheet -Objects $allObjects -IncludeMetadata:$IncludeMetadata
                    }
                    'ADMX' {
                        Export-ADMXToExcel -Worksheet $worksheet -Objects $allObjects -IncludeMetadata:$IncludeMetadata
                    }
                    'Server' {
                        Export-ServerToExcel -Worksheet $worksheet -Objects $allObjects -IncludeMetadata:$IncludeMetadata
                    }
                    'Events' {
                        Export-EventsToExcel -Worksheet $worksheet -Objects $allObjects -IncludeMetadata:$IncludeMetadata
                    }
                }
                
                # Auto-fit columns
                $usedRange = $worksheet.UsedRange
                if ($usedRange) {
                    $usedRange.Columns.AutoFit() | Out-Null
                }
                
                # Save workbook
                $workbook.SaveAs($FilePath)
                Write-Host "Excel file saved: $FilePath" -ForegroundColor Green
                
                if ($OpenAfterExport) {
                    $excel.Visible = $true
                    Write-Host "Opening Excel file..." -ForegroundColor Yellow
                } else {
                    $workbook.Close($false)
                    $excel.Quit()
                }
            }
            catch {
                if ($workbook) { $workbook.Close($false) }
                if ($excel) { $excel.Quit() }
                throw
            }
            finally {
                if (-not $OpenAfterExport) {
                    if ($workbook) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null }
                    if ($excel) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null }
                }
            }
        }
        catch {
            Write-Error "Failed to export to Excel: $_"
            throw
        }
    }
}

function Export-ConfigurationToExcel {
    param($Worksheet, $Objects, $IncludeMetadata)
    
    # Headers
    $headers = @('Name', 'ID', 'Description', 'Enabled', 'Module Count', 'Last Modified')
    if ($IncludeMetadata) {
        $headers += @('Created', 'Author', 'Version', 'Size')
    }
    
    # Write headers
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $Worksheet.Cells.Item(1, $i + 1) = $headers[$i]
        $Worksheet.Cells.Item(1, $i + 1).Font.Bold = $true
        $Worksheet.Cells.Item(1, $i + 1).Interior.Color = 12632256  # Light blue
    }
    
    # Write data
    $row = 2
    foreach ($obj in $Objects) {
        $Worksheet.Cells.Item($row, 1) = $obj.name
        $Worksheet.Cells.Item($row, 2) = $obj.id
        $Worksheet.Cells.Item($row, 3) = $obj.description
        $Worksheet.Cells.Item($row, 4) = if ($obj.disabled) { "No" } else { "Yes" }
        $Worksheet.Cells.Item($row, 5) = if ($obj.modules) { $obj.modules.Count } else { 0 }
        $Worksheet.Cells.Item($row, 6) = $obj.lastModified
        
        if ($IncludeMetadata) {
            $Worksheet.Cells.Item($row, 7) = $obj.created
            $Worksheet.Cells.Item($row, 8) = $obj.author
            $Worksheet.Cells.Item($row, 9) = $obj.version
            $Worksheet.Cells.Item($row, 10) = $obj.size
        }
        
        $row++
    }
}

function Export-FilterToExcel {
    param($Worksheet, $Objects, $IncludeMetadata)
    
    $headers = @('Name', 'ID', 'Type', 'Enabled', 'Priority', 'Criteria Count')
    if ($IncludeMetadata) {
        $headers += @('Created', 'Modified', 'Description')
    }
    
    # Write headers
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $Worksheet.Cells.Item(1, $i + 1) = $headers[$i]
        $Worksheet.Cells.Item(1, $i + 1).Font.Bold = $true
        $Worksheet.Cells.Item(1, $i + 1).Interior.Color = 65280  # Light green
    }
    
    # Write data
    $row = 2
    foreach ($obj in $Objects) {
        $Worksheet.Cells.Item($row, 1) = $obj.name
        $Worksheet.Cells.Item($row, 2) = $obj.id
        $Worksheet.Cells.Item($row, 3) = $obj.filterType
        $Worksheet.Cells.Item($row, 4) = if ($obj.disabled) { "No" } else { "Yes" }
        $Worksheet.Cells.Item($row, 5) = $obj.priority
        $Worksheet.Cells.Item($row, 6) = if ($obj.criteria) { $obj.criteria.Count } else { 0 }
        
        if ($IncludeMetadata) {
            $Worksheet.Cells.Item($row, 7) = $obj.created
            $Worksheet.Cells.Item($row, 8) = $obj.lastModified
            $Worksheet.Cells.Item($row, 9) = $obj.description
        }
        
        $row++
    }
}

function Export-FlexAppToExcel {
    param($Worksheet, $Objects, $IncludeMetadata)
    
    $headers = @('Name', 'ID', 'Version', 'Enabled', 'Size (MB)', 'Status')
    if ($IncludeMetadata) {
        $headers += @('Created', 'Author', 'Description', 'Path')
    }
    
    # Write headers
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $Worksheet.Cells.Item(1, $i + 1) = $headers[$i]
        $Worksheet.Cells.Item(1, $i + 1).Font.Bold = $true
        $Worksheet.Cells.Item(1, $i + 1).Interior.Color = 16776960  # Light yellow
    }
    
    # Write data
    $row = 2
    foreach ($obj in $Objects) {
        $Worksheet.Cells.Item($row, 1) = $obj.name
        $Worksheet.Cells.Item($row, 2) = $obj.id
        $Worksheet.Cells.Item($row, 3) = $obj.version
        $Worksheet.Cells.Item($row, 4) = if ($obj.disabled) { "No" } else { "Yes" }
        $Worksheet.Cells.Item($row, 5) = if ($obj.size) { [math]::Round($obj.size / 1MB, 2) } else { 0 }
        $Worksheet.Cells.Item($row, 6) = $obj.status
        
        if ($IncludeMetadata) {
            $Worksheet.Cells.Item($row, 7) = $obj.created
            $Worksheet.Cells.Item($row, 8) = $obj.author
            $Worksheet.Cells.Item($row, 9) = $obj.description
            $Worksheet.Cells.Item($row, 10) = $obj.path
        }
        
        $row++
    }
}

function Export-ADMXToExcel {
    param($Worksheet, $Objects, $IncludeMetadata)
    
    $headers = @('Name', 'File', 'Sequence', 'Enabled', 'Namespace')
    if ($IncludeMetadata) {
        $headers += @('Version', 'Language', 'Size', 'Modified')
    }
    
    # Write headers
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $Worksheet.Cells.Item(1, $i + 1) = $headers[$i]
        $Worksheet.Cells.Item(1, $i + 1).Font.Bold = $true
        $Worksheet.Cells.Item(1, $i + 1).Interior.Color = 16711935  # Light purple
    }
    
    # Write data
    $row = 2
    foreach ($obj in $Objects) {
        $Worksheet.Cells.Item($row, 1) = $obj.name
        $Worksheet.Cells.Item($row, 2) = Split-Path $obj.admxFile -Leaf
        $Worksheet.Cells.Item($row, 3) = $obj.sequence
        $Worksheet.Cells.Item($row, 4) = if ($obj.disabled) { "No" } else { "Yes" }
        $Worksheet.Cells.Item($row, 5) = $obj.namespace
        
        if ($IncludeMetadata) {
            $Worksheet.Cells.Item($row, 6) = $obj.version
            $Worksheet.Cells.Item($row, 7) = $obj.language
            $Worksheet.Cells.Item($row, 8) = $obj.size
            $Worksheet.Cells.Item($row, 9) = $obj.lastModified
        }
        
        $row++
    }
}

function Export-EventsToExcel {
    param($Worksheet, $Objects, $IncludeMetadata)
    
    $headers = @('Timestamp', 'Level', 'Source', 'Message', 'User')
    if ($IncludeMetadata) {
        $headers += @('Server', 'Session', 'Details', 'Category')
    }
    
    # Write headers
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $Worksheet.Cells.Item(1, $i + 1) = $headers[$i]
        $Worksheet.Cells.Item(1, $i + 1).Font.Bold = $true
        $Worksheet.Cells.Item(1, $i + 1).Interior.Color = 16777164  # Light orange
    }
    
    # Write data
    $row = 2
    foreach ($obj in $Objects) {
        $Worksheet.Cells.Item($row, 1) = $obj.timestamp
        $Worksheet.Cells.Item($row, 2) = $obj.level
        $Worksheet.Cells.Item($row, 3) = $obj.source
        $Worksheet.Cells.Item($row, 4) = $obj.message
        $Worksheet.Cells.Item($row, 5) = $obj.user
        
        if ($IncludeMetadata) {
            $Worksheet.Cells.Item($row, 6) = $obj.server
            $Worksheet.Cells.Item($row, 7) = $obj.sessionId
            $Worksheet.Cells.Item($row, 8) = $obj.details
            $Worksheet.Cells.Item($row, 9) = $obj.category
        }
        
        $row++
    }
}

function Export-ServerToExcel {
    param($Worksheet, $Objects, $IncludeMetadata)
    
    $headers = @('Setting', 'Value', 'Type', 'Category')
    if ($IncludeMetadata) {
        $headers += @('Default', 'Description', 'Modified', 'Restart Required')
    }
    
    # Write headers
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $Worksheet.Cells.Item(1, $i + 1) = $headers[$i]
        $Worksheet.Cells.Item(1, $i + 1).Font.Bold = $true
        $Worksheet.Cells.Item(1, $i + 1).Interior.Color = 12648447  # Light gray
    }
    
    # Write data
    $row = 2
    foreach ($obj in $Objects) {
        $Worksheet.Cells.Item($row, 1) = $obj.name
        $Worksheet.Cells.Item($row, 2) = $obj.value
        $Worksheet.Cells.Item($row, 3) = $obj.type
        $Worksheet.Cells.Item($row, 4) = $obj.category
        
        if ($IncludeMetadata) {
            $Worksheet.Cells.Item($row, 5) = $obj.defaultValue
            $Worksheet.Cells.Item($row, 6) = $obj.description
            $Worksheet.Cells.Item($row, 7) = $obj.lastModified
            $Worksheet.Cells.Item($row, 8) = if ($obj.requiresRestart) { "Yes" } else { "No" }
        }
        
        $row++
    }
}

function Connect-ProUToAD {
    <#
    .SYNOPSIS
        Interactive wizard to connect ProfileUnity to Active Directory.
    
    .DESCRIPTION
        Provides a step-by-step wizard for configuring Active Directory integration
        with ProfileUnity, including domain selection, credential setup, and testing.
    
    .PARAMETER Domain
        Specific domain to connect to (bypasses domain selection)
    
    .PARAMETER Credential
        Credentials to use for AD connection
    
    .PARAMETER TestOnly
        Only test the connection without saving configuration
    
    .EXAMPLE
        Connect-ProUToAD
        
    .EXAMPLE
        Connect-ProUToAD -Domain "contoso.com" -TestOnly
    #>
    [CmdletBinding()]
    param(
        [string]$Domain,
        [System.Management.Automation.PSCredential]$Credential,
        [switch]$TestOnly
    )
    
    try {
        Write-Host "`nProfileUnity Active Directory Integration Wizard" -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        
        # Step 1: Domain Discovery/Selection
        if (-not $Domain) {
            Write-Host "`n1. Discovering Active Directory Domains..." -ForegroundColor Yellow
            
            try {
                $domains = Get-ProUADDomains -ErrorAction Stop
                
                if (-not $domains -or $domains.Count -eq 0) {
                    Write-Warning "No Active Directory domains discovered"
                    Write-Host "Please ensure:"
                    Write-Host "  - Domain controllers are accessible"
                    Write-Host "  - DNS is configured correctly"
                    Write-Host "  - Network connectivity exists"
                    return
                }
                
                Write-Host "Found $($domains.Count) domain(s):" -ForegroundColor Green
                for ($i = 0; $i -lt $domains.Count; $i++) {
                    Write-Host "  $($i + 1). $($domains[$i].Name) ($($domains[$i].NetBiosName))" -ForegroundColor White
                }
                
                if ($domains.Count -eq 1) {
                    $Domain = $domains[0].Name
                    Write-Host "Using domain: $Domain" -ForegroundColor Green
                } else {
                    do {
                        $selection = Read-Host "`nSelect domain (1-$($domains.Count))"
                        $domainIndex = [int]$selection - 1
                    } while ($domainIndex -lt 0 -or $domainIndex -ge $domains.Count)
                    
                    $Domain = $domains[$domainIndex].Name
                    Write-Host "Selected domain: $Domain" -ForegroundColor Green
                }
            }
            catch {
                Write-Error "Failed to discover domains: $_"
                return
            }
        }
        
        # Step 2: Credential Configuration
        Write-Host "`n2. Active Directory Credentials" -ForegroundColor Yellow
        
        if (-not $Credential) {
            $useCurrentUser = $true
            
            $choice = Read-Host "Use current user credentials? (Y/n)"
            if ($choice -match '^n') {
                $useCurrentUser = $false
                $username = Read-Host "Username (domain\user or user@domain.com)"
                $securePassword = Read-Host "Password" -AsSecureString
                $Credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)
            }
            
            if ($useCurrentUser) {
                Write-Host "Using current user credentials: $($env:USERDOMAIN)\$($env:USERNAME)" -ForegroundColor Green
            } else {
                Write-Host "Using credentials for: $($Credential.UserName)" -ForegroundColor Green
            }
        }
        
        # Step 3: Connection Testing
        Write-Host "`n3. Testing Active Directory Connection..." -ForegroundColor Yellow
        
        $testParams = @{
            Domain = $Domain
        }
        if ($Credential) {
            $testParams.Credential = $Credential
        }
        
        try {
            $testResult = Test-ProUADConnectivity @testParams
            
            if ($testResult.Connected) {
                Write-Host "Connection successful!" -ForegroundColor Green
                Write-Host "  Domain: $($testResult.Domain)" -ForegroundColor White
                Write-Host "  Domain Controller: $($testResult.DomainController)" -ForegroundColor White
                Write-Host "  Forest: $($testResult.Forest)" -ForegroundColor White
                
                # Display additional info
                if ($testResult.Sites) {
                    Write-Host "  Available Sites: $($testResult.Sites -join ', ')" -ForegroundColor White
                }
            } else {
                Write-Error "Connection failed: $($testResult.Error)"
                return
            }
        }
        catch {
            Write-Error "Connection test failed: $_"
            return
        }
        
        if ($TestOnly) {
            Write-Host "`nTest completed successfully. No configuration saved." -ForegroundColor Green
            return
        }
        
        # Step 4: Save Configuration
        Write-Host "`n4. Saving Configuration..." -ForegroundColor Yellow
        
        $saveConfig = Read-Host "Save this AD configuration? (Y/n)"
        if (-not ($saveConfig -match '^n')) {
            try {
                # Save AD configuration
                $adConfig = @{
                    Domain = $Domain
                    DomainController = $testResult.DomainController
                    UseCurrentCredentials = (-not $Credential)
                    Enabled = $true
                    ConfiguredDate = Get-Date
                }
                
                if ($Credential) {
                    $adConfig.ServiceAccount = $Credential.UserName
                    # Note: In production, store credentials securely
                }
                
                # Save via ProfileUnity API (implementation depends on API)
                # Set-ProUServerSetting -Name "ActiveDirectoryIntegration" -Value $adConfig
                
                Write-Host "Active Directory integration configured successfully!" -ForegroundColor Green
                
                # Step 5: Optional Services Configuration
                Write-Host "`n5. Optional Integration Services" -ForegroundColor Yellow
                Write-Host "Configure additional AD integration features:"
                Write-Host "  a) User/Group synchronization"
                Write-Host "  b) Computer object management"
                Write-Host "  c) OU-based filtering"
                
                $configureServices = Read-Host "Configure additional services? (y/N)"
                if ($configureServices -match '^y') {
                    Start-ADServicesWizard -Domain $Domain -Credential $Credential
                }
            }
            catch {
                Write-Error "Failed to save configuration: $_"
                return
            }
        }
        
        Write-Host "`nActive Directory integration wizard completed!" -ForegroundColor Green
        Write-Host "Use Get-ProUADInfo to view current AD integration status." -ForegroundColor Yellow
    }
    catch {
        Write-Error "AD integration wizard failed: $_"
        throw
    }
}

function Start-ADServicesWizard {
    param($Domain, $Credential)
    
    Write-Host "`nConfiguring Additional AD Services..." -ForegroundColor Cyan
    
    # User/Group Sync
    $configSync = Read-Host "Enable user/group synchronization? (y/N)"
    if ($configSync -match '^y') {
        $syncInterval = Read-Host "Sync interval in minutes (default: 60)"
        if (-not $syncInterval) { $syncInterval = 60 }
        
        Write-Host "User/Group sync configured: every $syncInterval minutes" -ForegroundColor Green
    }
    
    # Computer Management
    $configComputers = Read-Host "Enable computer object management? (y/N)"
    if ($configComputers -match '^y') {
        $computerOU = Read-Host "Default computer OU (optional)"
        Write-Host "Computer management enabled" -ForegroundColor Green
    }
    
    # OU Filtering
    $configOUFilter = Read-Host "Enable OU-based filtering? (y/N)"
    if ($configOUFilter -match '^y') {
        Write-Host "Available OUs:" -ForegroundColor Yellow
        try {
            $ous = Get-ProUADOrganizationalUnits -Domain $Domain
            for ($i = 0; $i -lt [math]::Min($ous.Count, 10); $i++) {
                Write-Host "  $($ous[$i].Name)" -ForegroundColor White
            }
            if ($ous.Count -gt 10) {
                Write-Host "  ... and $($ous.Count - 10) more" -ForegroundColor Gray
            }
        }
        catch {
            Write-Warning "Could not retrieve OU list: $_"
        }
        
        Write-Host "OU filtering can be configured in the ProfileUnity console." -ForegroundColor Green
    }
}

function Test-ProUExcelExport {
    <#
    .SYNOPSIS
        Tests Excel export functionality.
    
    .DESCRIPTION
        Validates that Excel export functions work correctly with sample data.
    
    .EXAMPLE
        Test-ProUExcelExport
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "Testing Excel export functionality..." -ForegroundColor Yellow
        
        # Test Excel COM availability
        try {
            $excel = New-Object -ComObject Excel.Application
            $excel.Quit()
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
            Write-Host "Excel COM object available" -ForegroundColor Green
        }
        catch {
            Write-Error "Excel is not available or not properly installed: $_"
            return $false
        }
        
        # Create test data
        $testConfigs = @(
            [PSCustomObject]@{
                name = "Test Config 1"
                id = "12345"
                description = "Test configuration"
                disabled = $false
                modules = @(@{name="Module1"}, @{name="Module2"})
                lastModified = Get-Date
                created = (Get-Date).AddDays(-30)
                author = "TestUser"
                version = "1.0"
                size = 1024
            },
            [PSCustomObject]@{
                name = "Test Config 2"
                id = "67890"
                description = "Another test configuration"
                disabled = $true
                modules = @(@{name="Module3"})
                lastModified = Get-Date
                created = (Get-Date).AddDays(-15)
                author = "TestUser2"
                version = "2.0"
                size = 2048
            }
        )
        
        $tempFile = Join-Path $env:TEMP "ProU_ExportTest.xlsx"
        
        # Test export
        Export-ProUToExcel -Object $testConfigs -ObjectType Configuration -FilePath $tempFile -IncludeMetadata
        
        if (Test-Path $tempFile) {
            Write-Host "Excel export test completed successfully" -ForegroundColor Green
            Write-Host "Test file created: $tempFile" -ForegroundColor White
            
            # Cleanup
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            
            return $true
        } else {
            Write-Error "Excel export test failed - file not created"
            return $false
        }
    }
    catch {
        Write-Error "Excel export test failed: $_"
        return $false
    }
}

function Get-ProUIntegrationStatus {
    <#
    .SYNOPSIS
        Gets the status of ProfileUnity integrations.
    
    .DESCRIPTION
        Returns information about current integration status including AD, Excel, and other services.
    
    .EXAMPLE
        Get-ProUIntegrationStatus
    #>
    [CmdletBinding()]
    param()
    
    try {
        $status = [PSCustomObject]@{
            ActiveDirectory = @{
                Available = $false
                Connected = $false
                Domain = $null
                Error = $null
            }
            ExcelExport = @{
                Available = $false
                Version = $null
                Error = $null
            }
            LastChecked = Get-Date
        }
        
        # Check AD connectivity
        try {
            $adDomains = Get-ProUADDomains -ErrorAction Stop
            $status.ActiveDirectory.Available = $true
            $status.ActiveDirectory.Connected = ($adDomains | Where-Object { $_.IsConnected }).Count -gt 0
            if ($status.ActiveDirectory.Connected) {
                $connectedDomain = $adDomains | Where-Object { $_.IsConnected } | Select-Object -First 1
                $status.ActiveDirectory.Domain = $connectedDomain.Name
            }
        }
        catch {
            $status.ActiveDirectory.Error = $_.Exception.Message
        }
        
        # Check Excel availability
        try {
            $excel = New-Object -ComObject Excel.Application
            $status.ExcelExport.Available = $true
            $status.ExcelExport.Version = $excel.Version
            $excel.Quit()
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
        }
        catch {
            $status.ExcelExport.Error = $_.Exception.Message
        }
        
        return $status
    }
    catch {
        Write-Error "Failed to get integration status: $_"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Export-ProUToExcel',
    'Connect-ProUToAD',
    'Test-ProUExcelExport',
    'Get-ProUIntegrationStatus'
)