<#
.SYNOPSIS
    Remediation script to restore the Write-IntuneLog function by saving it to the correct file path.

.DESCRIPTION
    This script restores or creates the Write-IntuneLog.ps1 file with the correct function content if it is missing or the version is incorrect.

.PARAMETER None

.EXAMPLE
    .\Remediate-WriteIntuneLog.ps1

.NOTES
    Author: Gary Smith [EUC Administrator]
    Date: 04/10/2024
#>

$FunctionDirectory = 'C:\ProgramData\EUC\Functions'
$FunctionFileName = 'Write-IntuneLog.ps1'
$FunctionFilePath = $FunctionDirectory + '\' + $FunctionFileName
$ExpectedVersion = 'Version: 1.0'

try {
    # Ensure the function directory exists
    if (-not (Test-Path -Path $FunctionDirectory)) {
        New-Item -Path $FunctionDirectory -ItemType Directory -Force | Out-Null
    }

    # Read the entire script into a variable
    $currentScript = Get-Content -Path $MyInvocation.MyCommand.Path -Raw

    # Find the position of the **last** "#!ENDOFSCRIPT!#" marker and extract everything after it
    $Marker = "#!ENDOFSCRIPT!#"
    $FunctionStartIndex = $currentScript.LastIndexOf($Marker) + $Marker.Length
    $FunctionContent = $currentScript.Substring($FunctionStartIndex).Trim()

    # Check if the file exists and contains the correct version
    if (Test-Path $FunctionFilePath) {
        $FileContent = Get-Content -Path $FunctionFilePath -Raw
        
        if ($FileContent -match [regex]::Escape($ExpectedVersion)) {
            $OutputMessage = "Write-IntuneLog function version is correct, no remediation required."
        } else {
            $OutputMessage = "Write-IntuneLog function version is incorrect, restoring the correct version."
            Set-Content -Path $FunctionFilePath -Value $FunctionContent
        }
    } else {
        $OutputMessage = "Write-IntuneLog.ps1 does not exist, creating the file."
        Set-Content -Path $FunctionFilePath -Value $FunctionContent
    }

    Write-Output $OutputMessage

} catch {
    # Handle any unexpected script errors
    Write-Error "An error occurred during remediation: $($_.Exception.Message)" -ErrorAction Stop
}

# The actual Write-IntuneLog function
#!ENDOFSCRIPT!#
Function Write-IntuneLog {
    <#
    .SYNOPSIS
        Writes log entries in CMTrace format to a specified log file with automatic archiving.
    .DESCRIPTION
        The Write-IntuneLog function is designed to log messages in a CMTrace-compatible format.
        The log file automatically archives itself when it exceeds 5MB, keeping a maximum of 5 archives.
    .PARAMETER Message
        The log message to be recorded.
    .PARAMETER Severity
        The severity level of the message. Options are: Info, Warning, Error.
    .PARAMETER LogFileName
        The name of the log file. Default is "EUC_System_Log.log".
    .EXAMPLE
        Write-IntuneLog -Message "This is an informational log entry." -Severity Info
    .NOTES
        Version: 1.1
        Author: Gary Smith [EUC Administrator]
        Date: 05/10/2024
        Revision: Updated to capture the calling script's name for logging.
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message, 
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Severity = 'Info',
        [string]$LogFileName = "EUC_System_Log.log"
    )
    
    # Convert Severity string to a number for logging
    $SeverityNumber = switch ($Severity) {
        'Info' { 1 }
        'Warning' { 2 }
        'Error' { 3 }
    }
    
    # Set log path and max log size
    $LogPath = "C:\ProgramData\EUC\Logs\"
    $LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
    $MaxLogSizeBytes = 5MB
    $MaxArchivedLogs = 5
    
    # Ensure log directory exists
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    # Archive the log if it exceeds the maximum size
    if (Test-Path $LogFile) {
        $logFileSize = (Get-Item $LogFile).Length
        if ($logFileSize -gt $MaxLogSizeBytes) {
            $ArchivedLogName = "$($LogFileName)_archived_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
            Rename-Item -Path $LogFile -NewName (Join-Path -Path $LogPath -ChildPath $ArchivedLogName) | Out-Null
    
            # Remove oldest logs if more than 5 archived logs exist
            $archivedLogs = Get-ChildItem -Path $LogPath -Filter "$($LogFileName)_archived_*.log" |
            Sort-Object LastWriteTime
    
            if ($archivedLogs.Count -gt $MaxArchivedLogs) {
                $logsToRemove = $archivedLogs | Select-Object -First ($archivedLogs.Count - $MaxArchivedLogs)
                Remove-Item -Path $logsToRemove.FullName -Force | Out-Null
            }
    
            # Create a new empty log file after archiving
            New-Item -Path $LogFile -ItemType File | Out-Null
        }
    }

    # Determine the calling script's name or use "Console" if called directly from the console
    $ScriptSource = if ($MyInvocation.PSCommandPath) {
        [System.IO.Path]::GetFileName($MyInvocation.PSCommandPath)
    }
    else {
        "Console"
    }
    
    # Construct the CMTrace-compatible log string for CMPowerLogViewer
    $LogTimePlusBias = (Get-Date).ToString('HH:mm:ss.fffzzz')
    $LogDate = (Get-Date).ToString('yyyy-MM-dd')
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    
    $CMTraceLogString = "<![LOG[$Message]LOG]!>" + `
        "<time=`"$LogTimePlusBias`" " + `
        "date=`"$LogDate`" " + `
        "component=`"$ScriptSource`" " + `
        "context=`"$CurrentUser`" " + `
        "type=`"$SeverityNumber`" " + `
        "thread=`"$PID`" " + `
        "file=`"$ScriptSource`">"
    
    # Append the CMTrace log string to the log file
    Add-Content -Path $LogFile -Value $CMTraceLogString
}

