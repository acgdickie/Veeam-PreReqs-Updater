# Read-only. Times each Veeam call that STEP 6B of Update-VeeamPreReqs.ps1 makes,
# so the slow one shows. It changes nothing. Results: C:\Temp\veeam-call-timing.txt
$ErrorActionPreference = 'Continue'
$out = 'C:\Temp\veeam-call-timing.txt'
New-Item -ItemType Directory -Path (Split-Path $out) -Force | Out-Null
$results = New-Object System.Collections.Generic.List[object]
if (-not $env:TIMING_TEST) {
    Import-Module Veeam.Backup.PowerShell -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
    try { Connect-VBRServer -Server localhost -ErrorAction Stop } catch {}
}

function Short($e) { $m = ("$($e.Exception.Message)" -replace '\s+', ' ').Trim(); if ($m.Length -gt 120) { $m.Substring(0, 120) + '...' } else { $m } }
function Write-Result([string] $Name, [double] $Seconds, [string] $Note) {
    $line = '{0:HH:mm:ss}  {1,-46} {2,8:n1} s  {3}' -f (Get-Date), $Name, $Seconds, $Note
    Write-Host $line
    Add-Content -LiteralPath $out -Value $line
    $results.Add([pscustomobject]@{ Name = $Name; Seconds = $Seconds; Note = $Note })
}
function Measure-Call([string] $Label, [scriptblock] $Call) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $items = @(& $Call); Write-Result $Label $sw.Elapsed.TotalSeconds ('{0:n0} items' -f $items.Count); return ,$items }
    catch { Write-Result $Label $sw.Elapsed.TotalSeconds ('failed: ' + (Short $_)); return ,@() }
}
# Like the update script: call a getter only when it has a parameter set with no
# mandatory parameter. A getter that is not on this server is left out.
function Measure-Bare([string] $Name) {
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $c) { return ,@() }
    $bare = [bool]@($c.ParameterSets | Where-Object { @($_.Parameters | Where-Object { $_.IsMandatory }).Count -eq 0 }).Count
    if (-not $bare) { Write-Result $Name 0 'skipped: needs a parameter on this build'; return ,@() }
    return Measure-Call $Name ([scriptblock]::Create("$Name -ErrorAction Stop -WarningAction SilentlyContinue"))
}
# A call made once per item: time the first 3, then estimate the total.
function Measure-PerItem([string] $Label, [object[]] $Items, [scriptblock] $Call) {
    if (@($Items).Count -eq 0) { Write-Result $Label 0 'nothing to query'; return }
    $sample = @($Items | Select-Object -First 3)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { foreach ($i in $sample) { [void]@(& $Call $i) } }
    catch { Write-Result $Label $sw.Elapsed.TotalSeconds ('failed: ' + (Short $_)); return }
    $each = $sw.Elapsed.TotalSeconds / $sample.Count
    Write-Result $Label ($each * @($Items).Count) ('estimate: {0:n1} s each x {1:n0}' -f $each, @($Items).Count)
}

$start = Get-Date
Add-Content -LiteralPath $out -Value "=== Veeam call timing on $env:COMPUTERNAME, $start ==="
Write-Host '--- Job lists (STEP 6B inventory, and again in every activity check) ---'
$jobs = @{}
foreach ($g in 'Get-VBRJob','Get-VBRComputerBackupJob','Get-VBRComputerBackupCopyJob','Get-VBRBackupCopyJob','Get-VBRTapeJob',
               'Get-VBRSureBackupJob','Get-VBRApplicationBackupJob','Get-VBRPluginJob','Get-VBREPJob','Get-VBRProtectionGroup',
               'Get-VBRCatalystCopyJob','Get-VBRStorageCopyJob','Get-VBRCDPPolicy','Get-VBRvCDReplicaJob','Get-VBRUnstructuredBackupJob',
               'Get-VBRUnstructuredBackupCopyJob','Get-VBREntraIDTenantBackupJob','Get-VBREntraIDLogsBackupJob','Get-VBRConfigurationBackupJob') {
    $jobs[$g] = Measure-Bare $g
}
Write-Host '--- Session lists (every activity check) ---'
foreach ($g in 'Get-VBRBackupSession','Get-VBRRestoreSession','Get-VBRTapeBackupSession','Get-VBRComputerBackupJobSession','Get-VBREPSession',
               'Get-VBRApplicationBackupJobSession','Get-VBRPluginBackupSession','Get-VBRPluginRestoreSession','Get-VBRSureBackupSession',
               'Get-VBRUnstructuredBackupFLRSession','Get-VBRADForestRestoreSession','Get-VBRAmazonRestoreSession','Get-VBRAzureRestoreSession',
               'Get-VBRAzureApplianceSession','Get-VBRCloudTapeRestoreSession','Get-VBREntraIDTenantRestoreSession','Get-VBRGoogleCloudRestoreSession',
               'Get-VBRExchangeItemRestoreSession','Get-VBRSharePointItemRestoreSession','Get-VBRInstantRecovery','Get-VBRNASInstantRecovery',
               'Get-VBRFCDInstantRecoverySession','Get-VBRPublishedBackupContentSession','Get-VBRPublishedBackupDiskSession','Get-VBRAzureInstantRecovery',
               'Get-VBRVirtualMachineStartSession','Get-VBRTestQuickMigrationSession','Get-VBRInstantRecoveryMigration','Get-VBRNASInstantRecoveryMigration',
               'Get-VEADRestoreSession','Get-VEHANARestoreSession','Get-VEMDBRestoreSession','Get-VEODRestoreSession','Get-VEORRestoreSession',
               'Get-VEORRMANRestoreSession','Get-VEPSQLRestoreSession','Get-VESQLPluginRestoreSession','Get-VESQLRDSRestoreSession','Get-VESQLRestoreSession') {
    [void](Measure-Bare $g)
}
if (Get-Command Get-VBRSession -ErrorAction SilentlyContinue) {
    foreach ($t in 'EpAgentDiscovery','EpAgentDiscoveryObsolete') {
        [void](Measure-Call "Get-VBRSession -Type $t" ([scriptblock]::Create("Get-VBRSession -Type $t -ErrorAction Stop")))
    }
}
Write-Host '--- Backup copy and move sessions ---'
$backups = $null
foreach ($g in 'Get-VBRCopyBackupSession','Get-VBRMoveBackupSession') {
    $c = Get-Command $g -ErrorAction SilentlyContinue
    if (-not $c) { continue }
    $bare = [bool]@($c.ParameterSets | Where-Object { @($_.Parameters | Where-Object { $_.IsMandatory }).Count -eq 0 }).Count
    if ($bare) { [void](Measure-Bare $g); continue }
    if ($null -eq $backups) { $backups = Measure-Call 'Get-VBRBackup' { Get-VBRBackup -ErrorAction Stop } }
    Measure-PerItem "$g -Backup (one per backup)" $backups ([scriptblock]::Create("param(`$b) $g -Backup `$b -ErrorAction Stop"))
}
Write-Host '--- File share and object storage sessions (one query per job, every activity check) ---'
$unstructured = @(@($jobs['Get-VBRUnstructuredBackupJob']) + @($jobs['Get-VBRUnstructuredBackupCopyJob']) | Where-Object { $_ })
if ($unstructured.Count -and (Get-Command Get-VBRUnstructuredBackupSession -ErrorAction SilentlyContinue)) {
    Measure-PerItem 'Get-VBRUnstructuredBackupSession -Name (one per job)' $unstructured {
        param($j) Get-VBRUnstructuredBackupSession -Name "$([WildcardPattern]::Escape("$($j.Name)"))*" -ErrorAction Stop
    }
}
if ($unstructured.Count -and ('Veeam.Backup.Core.CBackupJob' -as [type])) {
    Measure-PerItem 'CBackupJob::Find (one per job, enabled state)' $unstructured {
        param($j) [Veeam.Backup.Core.CBackupJob]::Find([guid]"$($j.Id)")
    }
}
$cdp = @($jobs['Get-VBRCDPPolicy'])
if ($cdp.Count -and (Get-Command Get-VBRCDPSession -ErrorAction SilentlyContinue)) {
    Measure-PerItem 'Get-VBRCDPSession -Policy (one per policy)' $cdp { param($p) Get-VBRCDPSession -Policy $p -Last -ErrorAction Stop }
}

$total = ((Get-Date) - $start).TotalMinutes
Write-Host ''
Write-Host ('=== Done in {0:n1} minutes. The 5 slowest: ===' -f $total)
$top = @($results | Sort-Object Seconds -Descending | Select-Object -First 5 | ForEach-Object { '{0,-46} {1,8:n1} s  {2}' -f $_.Name, $_.Seconds, $_.Note })
$top | ForEach-Object { Write-Host $_ }
Add-Content -LiteralPath $out -Value (@('', ('=== Done in {0:n1} minutes. The 5 slowest: ===' -f $total)) + $top)
Write-Host "Saved to $out"
