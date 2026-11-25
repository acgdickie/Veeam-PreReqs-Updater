# Test-UnstructuredDisable.ps1
# Proves whether Disable-VBRJob / Enable-VBRJob (the console's right-click Disable) keeps the
# schedule of a file share or object storage backup job.
# For each job named in -JobName it: reads the job, disables it, reads it, enables it, reads it.
# The job is off for a few seconds only. If the enable fails, the script tries again and tells you.
# Run in Windows PowerShell 5.1, as administrator, on the VBR server, when the jobs are not running.
# Output: C:\Temp\veeam-disable-test-<time>.txt
param([Parameter(Mandatory)][string[]] $JobName)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path C:\Temp -Force | Out-Null
$out = "C:\Temp\veeam-disable-test-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
Start-Transcript -Path $out | Out-Null

function Show-Json($object) {
    try { $object | ConvertTo-Json -Depth 4 -Compress } catch { "(could not convert: $($_.Exception.Message))" }
}

function Read-State([string] $id) {
    $ps = @(Get-VBRUnstructuredBackupJob | Where-Object { "$($_.Id)" -eq $id })
    $core = [Veeam.Backup.Core.CBackupJob]::Find([guid]$id)
    $runManually = '(unreadable)'
    try { $runManually = "$($core.Options.JobOptions.RunManually)" } catch {}
    [pscustomobject]@{
        PsScheduleEnabled   = "$($ps[0].ScheduleEnabled)"
        PsScheduleOptions   = Show-Json $ps[0].ScheduleOptions
        CoreDisableFlagOn   = "$($core.IsScheduleEnabled)"
        CoreRunManually     = $runManually
        CoreScheduleOptions = Show-Json $core.ScheduleOptions
    }
}

function Show-State([string] $label, $state) {
    "  [$label]"
    "    ScheduleEnabled (PS object)  : $($state.PsScheduleEnabled)"
    "    IsScheduleEnabled (CBackupJob): $($state.CoreDisableFlagOn)"
    "    RunManually (CBackupJob)     : $($state.CoreRunManually)"
    "    ScheduleOptions (PS object)  : $($state.PsScheduleOptions)"
    "    ScheduleOptions (CBackupJob) : $($state.CoreScheduleOptions)"
}

try {
    Import-Module Veeam.Backup.PowerShell -WarningAction SilentlyContinue
    foreach ($name in $JobName) {
        "`n===== $name  [$(Get-Date -Format 'HH:mm:ss')] ====="
        $jobs = @(Get-VBRUnstructuredBackupJob | Where-Object { $_.Name -eq $name })
        if ($jobs.Count -ne 1) { "  SKIP: found $($jobs.Count) unstructured job(s) with this name"; continue }
        $id = "$($jobs[0].Id)"
        "  Type: $($jobs[0].GetType().FullName)"
        $before = Read-State $id
        Show-State 'before' $before
        if ($before.CoreDisableFlagOn -ne 'True') { "  SKIP: the job is already disabled in the console"; continue }

        $core = [Veeam.Backup.Core.CBackupJob]::Find([guid]$id)
        $disabled = $false
        try {
            Disable-VBRJob -Job $core -WarningAction Continue | Out-Null
            $disabled = $true
            $off = Read-State $id
            Show-State 'after Disable-VBRJob' $off
        } catch {
            "  Disable-VBRJob FAILED: $($_.Exception.Message)"
        } finally {
            $core = [Veeam.Backup.Core.CBackupJob]::Find([guid]$id)
            if ($disabled -or "$($core.IsScheduleEnabled)" -ne 'True') {
                try { Enable-VBRJob -Job $core -WarningAction Continue | Out-Null }
                catch {
                    "  Enable-VBRJob FAILED: $($_.Exception.Message)"
                    try { Enable-VBRJob -Job ([Veeam.Backup.Core.CBackupJob]::Find([guid]$id)) | Out-Null } catch {}
                }
            }
        }
        $after = Read-State $id
        Show-State 'after Enable-VBRJob' $after
        if ($after.CoreDisableFlagOn -ne 'True') { "  !!! THE JOB IS STILL DISABLED. Enable it in the console now. !!!" }

        "  RESULT:"
        "    Disable turned it off      : $(if ($off) { $off.CoreDisableFlagOn -eq 'False' } else { 'n/a' })"
        "    Enable turned it back on   : $($after.CoreDisableFlagOn -eq 'True')"
        "    PS schedule same as before : $($after.PsScheduleEnabled -eq $before.PsScheduleEnabled -and $after.PsScheduleOptions -eq $before.PsScheduleOptions)"
        "    Core schedule same as before: $($after.CoreRunManually -eq $before.CoreRunManually -and $after.CoreScheduleOptions -eq $before.CoreScheduleOptions)"
        if ($off) {
            "    Schedule kept while off    : $($off.PsScheduleOptions -eq $before.PsScheduleOptions -and $off.CoreRunManually -eq $before.CoreRunManually)"
        }
    }
} catch {
    "STOPPED: $($_.Exception.Message)"
} finally {
    Stop-Transcript | Out-Null
    "Saved to $out"
}
