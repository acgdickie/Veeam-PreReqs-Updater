# Probe-GetRunning.ps1 - READ-ONLY. Changes nothing.
# Times Veeam's own lists of running sessions, CBackupSession::GetRunning() and
# CBaseSession::GetRunning(), and checks them against the slow lists the update
# script reads today: Get-VBRBackupSession (about 10 minutes on a big server),
# Get-VBRUnstructuredBackupSession -Name '*' and Get-VBRRestoreSession.
# Run it while at least one Veeam job runs: best a file share or object storage job
# and a backup or backup copy job. Not during an -Install.
# -Quick skips the slow lists, to time GetRunning() alone.
# Run in Windows PowerShell 5.1, as administrator, on the VBR server.
# Output: C:\Temp\veeam-getrunning-probe-<time>.txt
param([switch] $Quick, [int] $Port = 5432, [string] $Database = 'VeeamBackup')

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path C:\Temp -Force | Out-Null
$out = "C:\Temp\veeam-getrunning-probe-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
Start-Transcript -Path $out | Out-Null

function Show-Time([string] $what) { Write-Host "`n===== $what  [$(Get-Date -Format 'HH:mm:ss')] =====" }
function Measure-Step([string] $Label, [scriptblock] $Block) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $items = @(& $Block)
        Write-Host ('{0,-52} {1,8:n1} s  {2:n0} item(s)' -f $Label, $sw.Elapsed.TotalSeconds, $items.Count)
        return ,$items
    } catch {
        Write-Host ('{0,-52} {1,8:n1} s  FAILED: {2}' -f $Label, $sw.Elapsed.TotalSeconds, $_.Exception.Message)
        return ,@()
    }
}
function Get-Prop($Object, [string] $Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { return "$($Object.$Name)" }
    return ''
}
function Show-Session([string] $Prefix, $Session) {
    $name = Get-Prop $Session 'JobName'; if (-not $name) { $name = Get-Prop $Session 'Name' }
    Write-Host ("  {0} {1} | {2} | type {3} | {4} | state {5} | created {6}" -f $Prefix, (Get-Prop $Session 'Id'), $name,
        (Get-Prop $Session 'JobType'), $Session.GetType().Name, (Get-Prop $Session 'State'), (Get-Prop $Session 'CreationTime'))
}
# The SQL goes in a file: Windows PowerShell 5.1 mangles double quotes in arguments.
$psql = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
function Invoke-ProbeSql([string] $Sql) {
    if (-not $psql) { throw 'psql.exe not found under C:\Program Files\PostgreSQL' }
    $sqlFile = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($sqlFile, $Sql)
        $lines = & $psql.FullName -U postgres -h 127.0.0.1 -p $Port -d $Database -w -t -A -F '|' -f $sqlFile 2>&1
        if ($LASTEXITCODE -ne 0) { throw "psql: $($lines -join ' ')" }
        return @($lines | Where-Object { "$_" -ne '' } | ForEach-Object { "$_" })
    } finally { Remove-Item -LiteralPath $sqlFile -Force -ErrorAction SilentlyContinue }
}

try {
    Show-Time 'Loading Veeam module'
    Import-Module Veeam.Backup.PowerShell -WarningAction SilentlyContinue -ErrorAction Stop
    [void](Measure-Step 'Get-VBRJob (loads the Veeam types)' { Get-VBRJob -WarningAction SilentlyContinue })

    Show-Time '1. Veeam''s running-session lists'
    $backupRunning = Measure-Step 'CBackupSession::GetRunning()' { [Veeam.Backup.Core.CBackupSession]::GetRunning() }
    foreach ($s in $backupRunning) { Show-Session 'CBackupSession' $s }
    $baseRunning = Measure-Step 'CBaseSession::GetRunning()' { [Veeam.Backup.Core.CBaseSession]::GetRunning() }
    foreach ($s in $baseRunning) { Show-Session 'CBaseSession' $s }
    $runningIds = @{}
    foreach ($s in @($backupRunning) + @($baseRunning)) { $runningIds["$(Get-Prop $s 'Id')"] = $true }

    Show-Time '1b. Each GetRunning() session, looked up by ID with the cmdlets used today'
    foreach ($id in @($runningIds.Keys | Where-Object { $_ })) {
        foreach ($cmd in 'Get-VBRBackupSession','Get-VBRUnstructuredBackupSession') {
            if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { continue }
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try {
                $hit = @(& $cmd -Id ([guid]$id) -ErrorAction Stop -WarningAction SilentlyContinue)
                $state = if ($hit.Count) { Get-Prop $hit[0] 'State' } else { '(not returned)' }
                Write-Host ('  {0,-34} -Id {1}  {2,6:n1} s  {3}' -f $cmd, $id, $sw.Elapsed.TotalSeconds, $state)
            } catch {
                Write-Host ('  {0,-34} -Id {1}  {2,6:n1} s  FAILED: {3}' -f $cmd, $id, $sw.Elapsed.TotalSeconds, $_.Exception.Message)
            }
        }
    }

    Show-Time '2. Sessions the database shows as not stopped (SELECT only)'
    try {
        $rows = Measure-Step 'backup.model.jobsessions where state <> -1' {
            Invoke-ProbeSql "SELECT concat_ws('|', id, coalesce(job_name, ''), job_type, state, creation_time, coalesce(end_time::text, '')) FROM public.`"backup.model.jobsessions`" WHERE state <> -1 ORDER BY creation_time"
        }
        foreach ($row in $rows) {
            $id = ($row -split '\|')[0]
            Write-Host "  db: $row | in GetRunning: $($runningIds.ContainsKey($id))"
        }
    } catch { Write-Host "  database read failed: $($_.Exception.Message)" }

    if ($Quick) {
        Show-Time 'Done (-Quick: the slow lists were skipped)'
    } else {
        Show-Time '3. The slow lists used today, to check GetRunning()'
        $missing = 0
        $truth = @{}
        $all = Measure-Step 'Get-VBRBackupSession' { Get-VBRBackupSession -ErrorAction Stop }
        $unstructured = @()
        if (Get-Command Get-VBRUnstructuredBackupSession -ErrorAction SilentlyContinue) {
            $unstructured = Measure-Step "Get-VBRUnstructuredBackupSession -Name '*'" { Get-VBRUnstructuredBackupSession -Name '*' -ErrorAction Stop }
        }
        $restores = Measure-Step 'Get-VBRRestoreSession' { Get-VBRRestoreSession -ErrorAction Stop }
        # Read GetRunning() again: a session that started while the slow lists were
        # read must not count as missed.
        $backupAfter = Measure-Step 'CBackupSession::GetRunning() again' { [Veeam.Backup.Core.CBackupSession]::GetRunning() }
        $baseAfter = Measure-Step 'CBaseSession::GetRunning() again' { [Veeam.Backup.Core.CBaseSession]::GetRunning() }
        foreach ($s in @($backupAfter) + @($baseAfter)) { $runningIds["$(Get-Prop $s 'Id')"] = $true }
        Write-Host '  Session types in Get-VBRBackupSession (count):'
        $all | Group-Object { Get-Prop $_ 'JobType' } | Sort-Object Count -Descending |
            ForEach-Object { Write-Host ("    {0,-36} {1:n0}" -f $_.Name, $_.Count) }
        foreach ($list in @(@{ Name = 'backup'; Items = $all }, @{ Name = 'unstructured'; Items = $unstructured }, @{ Name = 'restore'; Items = $restores })) {
            foreach ($s in @($list.Items | Where-Object { (Get-Prop $_ 'State') -and (Get-Prop $_ 'State') -ne 'Stopped' })) {
                $id = Get-Prop $s 'Id'
                $truth[$id] = $true
                $found = $runningIds.ContainsKey($id)
                if (-not $found) { $missing++ }
                Show-Session "$($list.Name), in GetRunning: $found |" $s
            }
        }
        Write-Host "`n  Running in the slow lists: $($truth.Count). Missing from GetRunning: $missing."
        $extra = @($runningIds.Keys | Where-Object { $_ -and -not $truth.ContainsKey($_) })
        Write-Host "  In GetRunning but not running in the slow lists: $($extra.Count)$(if ($extra.Count) { ' (' + ($extra -join ', ') + ')' })"
        Show-Time 'Done'
    }
} catch {
    Write-Host "STOPPED: $($_.Exception.Message)"
} finally {
    Stop-Transcript | Out-Null
    Write-Host "Saved to $out"
}
