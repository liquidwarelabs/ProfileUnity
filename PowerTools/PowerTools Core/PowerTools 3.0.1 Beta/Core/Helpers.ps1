# Helpers.ps1 - Common Helper Functions

function Confirm-Action {
    <#
    .SYNOPSIS
        Prompts user for confirmation before proceeding.
    
    .DESCRIPTION
        Shows a confirmation dialog for sensitive operations.
    
    .PARAMETER Title
        The title of the confirmation dialog
    
    .PARAMETER Message
        The message to display
    
    .EXAMPLE
        if (Confirm-Action -Title "Delete Configuration" -Message "Are you sure?") { }
    #>
    [CmdletBinding()]
    param(
        [string]$Title = "Confirm Action",
        [string]$Message = "Do you want to continue?"
    )
    
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Proceed with the action")
        [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Cancel the action")
    )
    
    $result = $host.UI.PromptForChoice($Title, $Message, $choices, 1)
    return $result -eq 0
}

function Get-FileName {
    <#
    .SYNOPSIS
        Shows a file selection dialog.
    
    .DESCRIPTION
        Opens a Windows file dialog for file selection.
    
    .PARAMETER Filter
        File type filter
    
    .PARAMETER InitialDirectory
        Starting directory for the dialog
    
    .PARAMETER Title
        Dialog window title
    
    .EXAMPLE
        $file = Get-FileName -Filter "JSON files (*.json)|*.json"
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = "All files (*.*)|*.*",
        [string]$InitialDirectory = [Environment]::GetFolderPath('MyDocuments'),
        [string]$Title = "Select File"
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    
    $dialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        InitialDirectory = $InitialDirectory
        Filter = $Filter
        Title = $Title
        RestoreDirectory = $true
    }
    
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.FileName
    }
    return $null
}

function Get-SaveFileName {
    <#
    .SYNOPSIS
        Shows a file save dialog.
    
    .DESCRIPTION
        Opens a Windows file dialog for saving files.
    
    .PARAMETER Filter
        File type filter
    
    .PARAMETER InitialDirectory
        Starting directory for the dialog
    
    .PARAMETER DefaultFileName
        Default file name
    
    .PARAMETER Title
        Dialog window title
    
    .EXAMPLE
        $file = Get-SaveFileName -Filter "JSON files (*.json)|*.json" -DefaultFileName "config.json"
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = "All files (*.*)|*.*",
        [string]$InitialDirectory = [Environment]::GetFolderPath('MyDocuments'),
        [string]$DefaultFileName = "",
        [string]$Title = "Save File"
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    
    $dialog = New-Object System.Windows.Forms.SaveFileDialog -Property @{
        InitialDirectory = $InitialDirectory
        Filter = $Filter
        FileName = $DefaultFileName
        Title = $Title
        RestoreDirectory = $true
        OverwritePrompt = $true
    }
    
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.FileName
    }
    return $null
}

function Get-FolderPath {
    <#
    .SYNOPSIS
        Shows a folder selection dialog.
    
    .DESCRIPTION
        Opens a Windows folder browser dialog.
    
    .PARAMETER Description
        Description shown in the dialog
    
    .PARAMETER InitialDirectory
        Starting directory
    
    .EXAMPLE
        $folder = Get-FolderPath -Description "Select export folder"
    #>
    [CmdletBinding()]
    param(
        [string]$Description = "Select Folder",
        [string]$InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
        Description = $Description
        SelectedPath = $InitialDirectory
        ShowNewFolderButton = $true
    }
    
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.SelectedPath
    }
    return $null
}

function Write-LogMessage {
    <#
    .SYNOPSIS
        Writes a message to the module log file.
    
    .DESCRIPTION
        Logs messages with timestamp and level.
    
    .PARAMETER Message
        The message to log
    
    .PARAMETER Level
        Log level (Info, Warning, Error)
    
    .EXAMPLE
        Write-LogMessage -Message "Operation completed" -Level Info
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to log file if available
    if ($script:LogFile) {
        try {
            Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not write to log file: $_"
        }
    }
    
    # Also write to verbose/warning/error stream based on level
    switch ($Level) {
        'Info' { Write-Verbose $Message }
        'Warning' { Write-Warning $Message }
        'Error' { Write-Error $Message }
        'Debug' { Write-Debug $Message }
    }
}

function ConvertTo-SafeFileName {
    <#
    .SYNOPSIS
        Converts a string to a safe filename.
    
    .DESCRIPTION
        Removes invalid characters from a filename.
    
    .PARAMETER FileName
        The filename to clean
    
    .EXAMPLE
        $safe = ConvertTo-SafeFileName -FileName "Config:Test/Invalid"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName
    )
    
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $pattern = '[' + [Regex]::Escape($invalidChars -join '') + ']'
    
    return $FileName -replace $pattern, '_'
}

function Test-JsonContent {
    <#
    .SYNOPSIS
        Tests if a string is valid JSON.
    
    .DESCRIPTION
        Validates JSON content and optionally returns the parsed object.
    
    .PARAMETER Json
        The JSON string to test
    
    .PARAMETER ReturnObject
        If specified, returns the parsed object
    
    .EXAMPLE
        if (Test-JsonContent -Json $jsonString) { }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Json,
        
        [switch]$ReturnObject
    )
    
    try {
        $obj = $Json | ConvertFrom-Json -ErrorAction Stop
        
        if ($ReturnObject) {
            return $obj
        }
        return $true
    }
    catch {
        if ($ReturnObject) {
            return $null
        }
        return $false
    }
}

function Format-ProfileUnityObject {
    <#
    .SYNOPSIS
        Formats ProfileUnity objects for display.
    
    .DESCRIPTION
        Creates a formatted view of common ProfileUnity objects.
    
    .PARAMETER Object
        The object to format
    
    .PARAMETER Type
        The type of object
    
    .EXAMPLE
        Format-ProfileUnityObject -Object $config -Type Configuration
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Object,
        
        [ValidateSet('Configuration', 'Filter', 'Portability', 'FlexApp')]
        [string]$Type
    )
    
    switch ($Type) {
        'Configuration' {
            return [PSCustomObject]@{
                Name = $Object.name
                ID = $Object.id
                Description = $Object.description
                Enabled = -not $Object.disabled
                ModuleCount = if ($Object.modules) { $Object.modules.Count } else { 0 }
                LastModified = $Object.lastModified
            }
        }
        'Filter' {
            return [PSCustomObject]@{
                Name = $Object.name
                ID = $Object.id
                Type = $Object.filterType
                Enabled = -not $Object.disabled
                Priority = $Object.priority
            }
        }
        'Portability' {
            return [PSCustomObject]@{
                Name = $Object.name
                ID = $Object.id
                Type = $Object.portabilityType
                Enabled = -not $Object.disabled
                Path = $Object.path
            }
        }
        'FlexApp' {
            return [PSCustomObject]@{
                Name = $Object.name
                ID = $Object.id
                Version = $Object.version
                Enabled = -not $Object.disabled
                Size = $Object.size
                Created = $Object.created
            }
        }
    }
}

function Get-ProfileUnityItemByName {
    <#
    .SYNOPSIS
        Gets a ProfileUnity item by exact name match.
    
    .DESCRIPTION
        Helper function to find items by exact name.
    
    .PARAMETER Items
        Collection of items to search
    
    .PARAMETER Name
        Name to find
    
    .PARAMETER Partial
        Allow partial name matching
    
    .EXAMPLE
        $config = Get-ProfileUnityItemByName -Items $configs -Name "Test Config"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Items,
        
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Partial
    )
    
    if ($Partial) {
        return $Items | Where-Object { $_.name -like "*$Name*" }
    }
    else {
        return $Items | Where-Object { $_.name -eq $Name }
    }
}

function Measure-ProfileUnityOperation {
    <#
    .SYNOPSIS
        Measures the time taken for an operation.
    
    .DESCRIPTION
        Executes a script block and measures execution time.
    
    .PARAMETER Operation
        The script block to execute
    
    .PARAMETER Name
        Name of the operation for logging
    
    .EXAMPLE
        Measure-ProfileUnityOperation -Name "Export" -Operation { }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Operation,
        
        [string]$Name = "Operation"
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        Write-Verbose "Starting $Name..."
        $result = & $Operation
        $stopwatch.Stop()
        
        Write-Verbose "$Name completed in $($stopwatch.Elapsed.TotalSeconds) seconds"
        Write-LogMessage -Message "$Name completed in $($stopwatch.Elapsed.TotalSeconds) seconds" -Level Info
        
        return $result
    }
    catch {
        $stopwatch.Stop()
        Write-LogMessage -Message "$Name failed after $($stopwatch.Elapsed.TotalSeconds) seconds: $_" -Level Error
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Confirm-Action',
    'Get-FileName',
    'Get-SaveFileName',
    'Get-FolderPath',
    'Write-LogMessage',
    'ConvertTo-SafeFileName',
    'Test-JsonContent',
    'Format-ProfileUnityObject',
    'Get-ProfileUnityItemByName',
    'Measure-ProfileUnityOperation'
)