[CmdletBinding()]
param(
	[switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:MonitoringActive = $true
$script:InitialPoolStates = @{}

$logFile = 'C:\Logs\iis-monitor.log'
$logDirectory = Split-Path -Path $logFile -Parent

if (-not (Test-Path -Path $logDirectory)) {
	New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

function Write-Log {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Message,

		[ValidateSet('INFO', 'WARN', 'ERROR')]
		[string]$Level = 'INFO'
	)

	$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
	$line = "[$timestamp] [$Level] $Message"
	Add-Content -Path $logFile -Value $line
	Write-Output $line
}

function Get-AppPoolStateSafe {
	param(
		[Parameter(Mandatory = $true)]
		[string]$PoolName
	)

	try {
		$state = Get-WebAppPoolState -Name $PoolName
		return $state.Value
	}
	catch {
		Write-Log -Level 'ERROR' -Message "Failed to get state for app pool '$PoolName'. $_"
		return $null
	}
}

function Get-RecentEventError {
	try {
		$startTime = (Get-Date).AddMinutes(-10)
		$events = Get-WinEvent -FilterHashtable @{
			LogName   = @('Application', 'System')
			Level     = 2
			StartTime = $startTime
		}

		if (-not $events) {
			Write-Log -Level 'INFO' -Message 'No Error-level Application/System events found in the last 10 minutes.'
			return
		}

		Write-Log -Level 'WARN' -Message "Captured $($events.Count) Error-level Application/System event(s) from the last 10 minutes."
		foreach ($logEvent in $events) {
			$eventMessage = ($logEvent.Message -replace '[\r\n]+', ' ').Trim()
			Write-Log -Level 'WARN' -Message "EventId=$($logEvent.Id); Log=$($logEvent.LogName); Provider=$($logEvent.ProviderName); Time=$($logEvent.TimeCreated); Message=$eventMessage"
		}
	}
	catch {
		Write-Log -Level 'ERROR' -Message "Failed to capture recent event log errors. $_"
	}
}

function Restart-AppPoolIfNeeded {
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
	param(
		[Parameter(Mandatory = $true)]
		[string]$PoolName
	)

	try {
		$currentState = Get-AppPoolStateSafe -PoolName $PoolName
		if (-not $currentState) {
			return
		}

		if ($currentState -eq 'Started') {
			Write-Log -Level 'INFO' -Message "App pool '$PoolName' is already running. Restart skipped (idempotent check)."
			return
		}

		if ($DryRun) {
			Write-Log -Level 'INFO' -Message "[DryRun] Would restart app pool '$PoolName'."
			return
		}

		if (-not $PSCmdlet.ShouldProcess($PoolName, 'Start IIS application pool')) {
			Write-Log -Level 'INFO' -Message "Restart cancelled by ShouldProcess for app pool '$PoolName'."
			return
		}

		Start-WebAppPool -Name $PoolName

		$postState = Get-AppPoolStateSafe -PoolName $PoolName
		if ($postState -eq 'Started') {
			Write-Log -Level 'INFO' -Message "Successfully started app pool '$PoolName'."
		}
		else {
			Write-Log -Level 'ERROR' -Message "Attempted to start app pool '$PoolName' but state is '$postState'."
		}
	}
	catch {
		Write-Log -Level 'ERROR' -Message "Failed to restart app pool '$PoolName'. $_"
	}
}

function Restore-AppPoolState {
	Write-Log -Level 'WARN' -Message 'Rollback initiated. Stopping monitoring loop and restoring initial app pool states.'
	$script:MonitoringActive = $false

	foreach ($poolName in $script:InitialPoolStates.Keys) {
		$expectedState = $script:InitialPoolStates[$poolName]

		try {
			$currentState = Get-AppPoolStateSafe -PoolName $poolName
			if (-not $currentState) {
				continue
			}

			if ($currentState -eq $expectedState) {
				Write-Log -Level 'INFO' -Message "Rollback check: app pool '$poolName' already in initial state '$expectedState'."
				continue
			}

			if ($DryRun) {
				Write-Log -Level 'INFO' -Message "[DryRun] Would set app pool '$poolName' from '$currentState' to '$expectedState'."
				continue
			}

			if ($expectedState -eq 'Started') {
				Start-WebAppPool -Name $poolName
				Write-Log -Level 'INFO' -Message "Rollback: started app pool '$poolName' to restore initial state."
			}
			elseif ($expectedState -eq 'Stopped') {
				Stop-WebAppPool -Name $poolName
				Write-Log -Level 'INFO' -Message "Rollback: stopped app pool '$poolName' to restore initial state."
			}
			else {
				Write-Log -Level 'WARN' -Message "Rollback: unhandled target state '$expectedState' for app pool '$poolName'."
			}
		}
		catch {
			Write-Log -Level 'ERROR' -Message "Rollback failed for app pool '$poolName'. $_"
		}
	}

	Write-Log -Level 'WARN' -Message 'Rollback complete. Monitoring loop has been stopped.'
}

try {
	Import-Module WebAdministration -ErrorAction Stop
}
catch {
	throw "Unable to import WebAdministration module. Run on a server with IIS and this module installed. $_"
}

try {
	$allPools = Get-ChildItem IIS:\AppPools
}
catch {
	throw "Unable to enumerate IIS app pools. Ensure the script is run as Administrator. $_"
}

foreach ($pool in $allPools) {
	$state = Get-AppPoolStateSafe -PoolName $pool.Name
	if ($state) {
		$script:InitialPoolStates[$pool.Name] = $state
	}
}

Write-Log -Level 'INFO' -Message "Monitoring started. Interval=60s. DryRun=$DryRun. Pools tracked=$($script:InitialPoolStates.Count)."

$exitEvent = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
	Restore-AppPoolState
}

try {
	while ($script:MonitoringActive) {
		try {
			$pools = Get-ChildItem IIS:\AppPools
		}
		catch {
			Write-Log -Level 'ERROR' -Message "Failed to enumerate app pools in monitoring loop. $_"
			Start-Sleep -Seconds 60
			continue
		}

		$stoppedPools = @()

		foreach ($pool in $pools) {
			$state = Get-AppPoolStateSafe -PoolName $pool.Name
			if ($state -eq 'Stopped') {
				$stoppedPools += $pool.Name
			}
		}

		if ($stoppedPools.Count -gt 0) {
			Write-Log -Level 'WARN' -Message "Detected stopped app pool(s): $($stoppedPools -join ', ')."
			Get-RecentEventError

			foreach ($poolName in $stoppedPools) {
				Restart-AppPoolIfNeeded -PoolName $poolName
			}
		}
		else {
			Write-Log -Level 'INFO' -Message 'All app pools are running.'
		}

		Start-Sleep -Seconds 60
	}
}
catch [System.Management.Automation.PipelineStoppedException] {
	Write-Log -Level 'WARN' -Message 'Monitoring interrupted (Ctrl+C or pipeline stop detected).'
	Restore-AppPoolState
}
catch {
	Write-Log -Level 'ERROR' -Message "Unhandled monitoring error. $_"
	Restore-AppPoolState
}
finally {
	if ($exitEvent) {
		Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
	}

	Write-Log -Level 'INFO' -Message 'Script exiting cleanly.'
}
