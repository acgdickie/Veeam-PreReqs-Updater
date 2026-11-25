# Probe-RunningSessions.ps1 - READ-ONLY. Changes nothing.
# Tries faster ways to find the Veeam sessions that run now, and times each one:
#   1. what the Veeam session types and cmdlets offer (names only, nothing is called)
#   2. each job's latest session, from its CBackupJob
#   3. the session tables in the Veeam database, read with psql (SELECT only)
#   4. Get-VBRUnstructuredBackupSession -Name '*', once
# Then it reads the full list the update script uses today (Get-VBRBackupSession,
# about 10 minutes on a big server), so each faster way can be checked against it.
# Best run while at least one Veeam job is running. Not during an -Install.
# Run in Windows PowerShell 5.1, as administrator, on the VBR server.
# Output: C:\Temp\veeam-session-probe-<time>.txt
param([int] $Port = 5432, [string] $Database = 'VeeamBackup')

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path C:\Temp -Force | Out-Null
$out = "C:\Temp\veeam-session-probe-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
Start-Transcript -Path $out | Out-Null

function Show-Time([string] $what) { Write-Host "`n===== $what  [$(Get-Date -Format 'HH:mm:ss')] =====" }
function Measure-Step([string] $Label, [scriptblock] $Block) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $items = @(& $Block)
        Write-Host ('{0,-58} {1,8:n1} s  {2:n0} item(s)' -f $Label, $sw.Elapsed.TotalSeconds, $items.Count)
        return ,$items
    } catch {
        Write-Host ('{0,-58} {1,8:n1} s  FAILED: {2}' -f $Label, $sw.Elapsed.TotalSeconds, $_.Exception.Message)
        return ,@()
    }
}
$psql = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
# The SQL goes in a file: Windows PowerShell 5.1 mangles double quotes in arguments.
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
    $vbrJobs = Measure-Step 'Get-VBRJob' { Get-VBRJob -WarningAction SilentlyContinue }

    Show-Time '1. What the session types and cmdlets offer (names only)'
    foreach ($typeName in 'Veeam.Backup.Core.CBackupSession','Veeam.Backup.Core.CBaseSession') {
        $type = $typeName -as [type]
        if (-not $type) { Write-Host "  $typeName : not loaded"; continue }
        $type.GetMethods([Reflection.BindingFlags]'Public,Static') |
            Where-Object { $_.Name -match 'Active|Running|Working|Last|Period|Since|After|Recent|Created|ByJob|State' } |
            ForEach-Object { "  $typeName::$($_.Name)($(@($_.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }) -join ', '))" } |
            Sort-Object -Unique | ForEach-Object { Write-Host $_ }
    }
    foreach ($cmd in 'Get-VBRBackupSession','Get-VBRSession','Get-VBRUnstructuredBackupSession') {
        $c = Get-Command $cmd -ErrorAction SilentlyContinue
        if (-not $c) { Write-Host "  $cmd : not found"; continue }
        foreach ($set in $c.ParameterSets) {
            $names = @($set.Parameters | Where-Object { $_.Name -notin [System.Management.Automation.PSCmdlet]::CommonParameters } | ForEach-Object { if ($_.IsMandatory) { "$($_.Name)*" } else { $_.Name } })
            Write-Host "  $cmd [$($set.Name)]: $($names -join ', ')"
        }
    }

    Show-Time '2. Each job''s latest session, from its CBackupJob'
    $jobIds = @{}
    foreach ($j in $vbrJobs) { $jobIds["$($j.Id)"] = "$($j.Name)" }
    foreach ($getter in 'Get-VBRBackupCopyJob','Get-VBRUnstructuredBackupJob','Get-VBRUnstructuredBackupCopyJob') {
        if (Get-Command $getter -ErrorAction SilentlyContinue) {
            foreach ($j in @(& $getter -WarningAction SilentlyContinue)) { $jobIds["$($j.Id)"] = "$($j.Name)" }
        }
    }
    $lastSessions = Measure-Step "CBackupJob.FindLastSession() for $($jobIds.Count) job(s)" {
        foreach ($id in $jobIds.Keys) {
            $core = [Veeam.Backup.Core.CBackupJob]::Find([guid]$id)
            if ($core) {
                $s = $core.FindLastSession()
                if ($s) { [pscustomobject]@{ Job = $jobIds[$id]; Id = "$($s.Id)"; State = "$($s.State)"; Created = $s.CreationTime; IsRunning = "$($core.IsRunning)" } }
            }
        }
    }
    $lastSessions | Where-Object { $_.State -ne 'Stopped' -or $_.IsRunning -eq 'True' } |
        ForEach-Object { Write-Host "  not stopped: $($_.Job) | session $($_.Id) | $($_.State) | IsRunning=$($_.IsRunning)" }

    Show-Time '3. Session tables in the Veeam database (SELECT only)'
    $tables = Measure-Step 'list session tables' {
        Invoke-ProbeSql "SELECT table_schema || '|' || table_name FROM information_schema.tables WHERE table_name ILIKE '%session%' ORDER BY 1"
    }
    $stateTables = @()
    foreach ($row in $tables) {
        $schema, $name = $row -split '\|', 2
        $columns = @(Invoke-ProbeSql "SELECT column_name FROM information_schema.columns WHERE table_schema = '$schema' AND table_name = '$name' ORDER BY ordinal_position")
        Write-Host "  $schema.`"$name`": $($columns -join ', ')"
        if ($columns -contains 'state' -and $columns -contains 'id') { $stateTables += [pscustomobject]@{ Schema = $schema; Name = $name; Columns = $columns } }
    }
    foreach ($t in $stateTables) {
        $counts = Measure-Step "count by state in `"$($t.Name)`"" {
            Invoke-ProbeSql "SELECT state || '|' || count(*) FROM `"$($t.Schema)`".`"$($t.Name)`" GROUP BY state ORDER BY state"
        }
        foreach ($c in $counts) { Write-Host "    state|count: $c" }
    }

    Show-Time '4. Get-VBRUnstructuredBackupSession -Name *, once'
    if (Get-Command Get-VBRUnstructuredBackupSession -ErrorAction SilentlyContinue) {
        $unstructured = Measure-Step "Get-VBRUnstructuredBackupSession -Name '*'" { Get-VBRUnstructuredBackupSession -Name '*' -ErrorAction Stop }
        $unstructured | Where-Object { "$($_.State)" -ne 'Stopped' } | ForEach-Object { Write-Host "  not stopped: $($_.Name) | $($_.State)" }
    }

    Show-Time '5. The full list used today (slow), to check the others'
    $all = Measure-Step 'Get-VBRBackupSession' { Get-VBRBackupSession -ErrorAction Stop }
    $running = @($all | Where-Object { "$($_.State)" -ne 'Stopped' })
    Write-Host "  sessions not stopped: $($running.Count)"
    foreach ($s in $running) {
        $byJob = @($lastSessions | Where-Object { $_.Id -eq "$($s.Id)" }).Count -gt 0
        Write-Host "  $($s.JobName) | session $($s.Id) | $($s.State) | created $($s.CreationTime) | found by way 2: $byJob"
        foreach ($t in $stateTables) {
            try {
                $dbState = @(Invoke-ProbeSql "SELECT state FROM `"$($t.Schema)`".`"$($t.Name)`" WHERE id = '$($s.Id)'")
                if ($dbState.Count) { Write-Host "    database `"$($t.Name)`" state: $($dbState -join ',')" }
            } catch {}
        }
    }
    $stoppedSample = @($all | Where-Object { "$($_.State)" -eq 'Stopped' } | Select-Object -Last 1)
    foreach ($s in $stoppedSample) {
        foreach ($t in $stateTables) {
            try {
                $dbState = @(Invoke-ProbeSql "SELECT state FROM `"$($t.Schema)`".`"$($t.Name)`" WHERE id = '$($s.Id)'")
                if ($dbState.Count) { Write-Host "  a stopped session ($($s.JobName)) in `"$($t.Name)`" has state: $($dbState -join ',')" }
            } catch {}
        }
    }
    Show-Time 'Done'
} catch {
    Write-Host "STOPPED: $($_.Exception.Message)"
} finally {
    Stop-Transcript | Out-Null
    Write-Host "Saved to $out"
}
