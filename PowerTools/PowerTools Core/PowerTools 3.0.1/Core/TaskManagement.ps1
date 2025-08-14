# Core/TaskManagement.ps1 - Task monitoring and management functions

function Get-ProUTask {
    <#
    .SYNOPSIS
        Gets ProfileUnity task information.
    
    .DESCRIPTION
        Retrieves information about running or completed tasks.
    
    .PARAMETER Id
        Specific task ID to retrieve
    
    .EXAMPLE
        Get-ProUTask
        
    .EXAMPLE
        Get-ProUTask -Id "12345-abc-def"
    #>
    [CmdletBinding()]
    param(
        [string]$Id
    )
    
    try {
        $endpoint = if ($Id) {
            "task/$Id"
        } else {
            "task"
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint $endpoint
        
        if ($Id) {
            return [PSCustomObject]@{
                Id = $response.id
                Name = $response.name
                Status = $response.status
                Progress = $response.progress
                StartTime = $response.startTime
                EndTime = $response.endTime
                Result = $response.result
                ErrorMessage = $response.errorMessage
            }
        }
        else {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_.id
                    Name = $_.name
                    Status = $_.status
                    Progress = $_.progress
                    StartTime = $_.startTime
                    EndTime = $_.endTime
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get task information: $_"
        throw
    }
}

function Stop-ProUTask {
    <#
    .SYNOPSIS
        Cancels a running ProfileUnity task.
    
    .DESCRIPTION
        Attempts to cancel a running task by its ID.
    
    .PARAMETER Id
        Task ID to cancel
    
    .EXAMPLE
        Stop-ProUTask -Id "12345-abc-def"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )
    
    if ($PSCmdlet.ShouldProcess("Task $Id", "Cancel")) {
        try {
            $response = Invoke-ProfileUnityApi -Endpoint "task/$Id/cancel" -Method POST
            
            Write-Host "Task cancellation requested: $Id" -ForegroundColor Yellow
            return $response
        }
        catch {
            Write-Error "Failed to cancel task: $_"
            throw
        }
    }
}

function Wait-ProUTask {
    <#
    .SYNOPSIS
        Waits for a ProfileUnity task to complete.
    
    .DESCRIPTION
        Monitors a task until it completes or times out.
    
    .PARAMETER Id
        Task ID to monitor
    
    .PARAMETER TimeoutMinutes
        Maximum time to wait in minutes (default: 30)
    
    .PARAMETER PollIntervalSeconds
        How often to check status in seconds (default: 5)
    
    .EXAMPLE
        Wait-ProUTask -Id "12345-abc-def"
        
    .EXAMPLE
        Wait-ProUTask -Id "12345-abc-def" -TimeoutMinutes 60 -PollIntervalSeconds 10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        
        [int]$TimeoutMinutes = 30,
        
        [int]$PollIntervalSeconds = 5
    )
    
    try {
        $startTime = Get-Date
        $timeoutTime = $startTime.AddMinutes($TimeoutMinutes)
        
        Write-Host "Waiting for task to complete: $Id" -ForegroundColor Yellow
        
        do {
            $task = Get-ProUTask -Id $Id
            
            Write-Host "Status: $($task.Status) - Progress: $($task.Progress)%" -ForegroundColor Cyan
            
            if ($task.Status -in @('Completed', 'Failed', 'Cancelled')) {
                break
            }
            
            Start-Sleep -Seconds $PollIntervalSeconds
            
        } while ((Get-Date) -lt $timeoutTime)
        
        if ((Get-Date) -ge $timeoutTime) {
            Write-Warning "Task monitoring timed out after $TimeoutMinutes minutes"
        }
        
        $finalTask = Get-ProUTask -Id $Id
        
        switch ($finalTask.Status) {
            'Completed' {
                Write-Host "Task completed successfully" -ForegroundColor Green
            }
            'Failed' {
                Write-Host "Task failed: $($finalTask.ErrorMessage)" -ForegroundColor Red
            }
            'Cancelled' {
                Write-Host "Task was cancelled" -ForegroundColor Yellow
            }
            default {
                Write-Host "Task status: $($finalTask.Status)" -ForegroundColor Yellow
            }
        }
        
        return $finalTask
    }
    catch {
        Write-Error "Failed to monitor task: $_"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ProUTask',
    'Stop-ProUTask', 
    'Wait-ProUTask'
)