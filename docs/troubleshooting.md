# If it goes wrong

This page explains what to do, case by case, when a run fails, is blocked, or was interrupted.

**In short**

- **Read the fields first:** `ExitCode`, `Stage`, `IssueCode`, `ActionRequired`, `JobsLeftDisabled`, `UnhealthyServices` and `RecoveryRunDir`.
- **The marker blocks runs:** a `CHANGES-IN-PROGRESS.marker` in the work root makes every normal audit/install return exit `40`. Do not delete it merely to make the next run proceed.
- **Use `-Recover`** for an interrupted run. After the installer started, it finishes the run only when everything proves it safe.
- **Do not use automatic database rollback** after an installer failure. Restoration is always an operator-reviewed operation.
- **`WshStatus=LEFT_ON` comes once.** Act on it the first time.

## First, read these fields

Read these report fields before you do anything else:

- `ExitCode`
- `Stage`
- `IssueCode`
- `ActionRequired`
- `JobsLeftDisabled`
- `UnhealthyServices`
- `RecoveryRunDir`

### Find your case

| What you see | Section below |
|---|---|
| Exit 40, `Stage=INSTALLING` | [Exit 40, Stage=INSTALLING](#exit-40-stageinstalling) |
| A leftover `CHANGES-IN-PROGRESS.marker` blocks the run (`PRIOR_RUN_INCOMPLETE`) | [Runs that changed nothing](#runs-that-changed-nothing), then [The CHANGES-IN-PROGRESS marker](#the-changes-in-progress-marker) |
| PostgreSQL marker at `VERIFIED`, Veeam services running, `-Recover` only reports | [Closing out an earlier run by hand](#closing-out-an-earlier-run-by-hand) |
| Exit 40, `Stage=VERIFIED` | [Exit 40, Stage=VERIFIED](#exit-40-stageverified) |
| Exit 40, `Stage=JOBS_DISABLED` or `SERVICES_STOPPED` | [Exit 40, Stage=JOBS_DISABLED or SERVICES_STOPPED](#exit-40-stagejobs_disabled-or-services_stopped) |
| Exit 50 | [Exit 50](#exit-50) |
| `WshStatus=LEFT_ON` | [WshStatus=LEFT_ON](#wshstatusleft_on) |
| `RECOVERY_MODULE_UNAVAILABLE` or `RECOVERY_DIAGNOSTIC_ONLY` | [Using -Recover](#using--recover) |
| Exit 40, `Stage=COMPLETE`, `IssueCode=MARKER_REMOVE_FAILED` | [Marker could not be removed](#marker-could-not-be-removed) |

## Exit 40, Stage=INSTALLING

The installer failed or timed out (`INSTALLER_FAILED`, `INSTALLER_TIMEOUT`).

- **Services** are stopped, and jobs are disabled.
- **Logs:** read `installer-*.log` and `pg_installer_debug.log` in `RecoveryRunDir`.
- **After `INSTALLER_TIMEOUT`**, the installer's own `install-postgresql*.log` and `bitrock_installer*.log` are not copied there yet. Look in `%TEMP%` and `C:\Windows\Temp`.
- **Rollback:** do not use automatic database rollback.

### Runs that changed nothing

These runs also report `Stage=INSTALLING`:

- a run blocked by a leftover marker (`PRIOR_RUN_INCOMPLETE`)
- a `-Recover` that refuses the marker or its recovery state

Exception: a refused NATS recovery keeps the stage it recorded.

Those runs changed nothing themselves. The server is as the earlier run left it.

A blocked run's `Detail` names:

- the earlier run
- its recorded stage
- how many Veeam services run now
- the next step for that stage

`RecoveryRunDir` is the earlier run's folder. The blocked run creates none. The whole marker is in the log.

## Closing out an earlier run by hand

This is only for a PostgreSQL run in this state:

- **Marker stage** is `VERIFIED` (PostgreSQL was already verified at its target).
- **Veeam services** already run.

In that state, `-Recover` only reports, because it cannot tell who started them.

A NATS run's `VERIFIED` marker is different: `-Recover` finishes it.

> [!IMPORTANT]
> A marker that is moved away no longer protects that run's log from the clean-up described in [Logs, backups and evidence](evidence.md). If you need the log, copy it before step 4.

To close the run out:

1. Check that PostgreSQL reports the target version and that the Veeam services are healthy.
2. On VB365: if `recovery-state.json` in `RecoveryRunDir` has a `Vb365MaintenanceSessionId`, end that repository maintenance session (`Stop-VBORepositoryMaintenanceSession -Id <id>`) and check the repositories have left maintenance mode.
3. In the Veeam console, check every job listed in `disabled-jobs.json` in `RecoveryRunDir`. Turn back on any that is still off. On VBR, run a configuration backup.
4. Move `CHANGES-IN-PROGRESS.marker` into that run folder (for example as `CHANGES-IN-PROGRESS.marker.closed-by-hand`), so it stays with the evidence.
5. Run an audit.

## Exit 40, Stage=VERIFIED

PostgreSQL updated fine, but one of these happened:

- a mandatory tuner failed
- a service did not come back
- a schedule could not be safely restored

The codes for this case are:

- `VEEAM_TUNING_FAILED`
- `SERVICES_UNHEALTHY_JOBS_DISABLED`
- `VB365_MAINTENANCE_RELEASE_FAILED`
- `FINAL_SESSION_CHECK_FAILED`
- `FINAL_JOB_DRAIN_TIMEOUT`
- `JOB_REENABLE_FAILED`

What the script does:

- **Schedules:** it leaves affected schedules disabled, to prevent jobs running against an unhealthy stack.
- **RMM summary** names the problem and the disabled schedules.
- **No reboot:** it never reboots in this case.

## Exit 40, Stage=JOBS_DISABLED or SERVICES_STOPPED

One of these happened:

- The run stopped before the installer started (or, on VB365, before the new NATS was verified), and putting things back did not fully succeed.
- A `-Recover` run could not finish.

The state of the server:

- **PostgreSQL** itself was not changed.
- **Stopped services:** PostgreSQL and the Veeam services may still be stopped.
- **Schedules** may still be disabled.
- **NATS** may be half-switched on a NATS run. See [NATS updates (VB365)](nats.md).
- **Marker** stays.

Where to look: `Detail` names the problem, and `JobsLeftDisabled` names the schedules.

What to do: fix the problem, then run `-Recover`.

## Exit 50

Exit 50 means one of these:

- PostgreSQL is missing, will not start, is not queryable, or reports the wrong version after install/tuning.
- `-Recover` diagnosed that emergency after the installer boundary.

What the script leaves:

- **Update failure:** Veeam services/schedules are deliberately left down or disabled.
- **Diagnostic-only recovery** does not change any service, job or PostgreSQL state it found.
- **Windows Script Host:** diagnostic-only recovery only turns it off again if the interrupted run left it on.

What to do: turn Windows Script Host on (Veeam KB4699) before you run the PostgreSQL installer by hand.

Before acting, use the exact `Stage`, `UnhealthyServices`, `JobsLeftDisabled`, and `ActionRequired` fields.

Recovery evidence includes:

- `runs\<timestamp>\backup\datadir\`
- its original DACL record in `datadir-acl.txt`
- validated logical dumps

Restoration is always an operator-reviewed operation.

## WshStatus=LEFT_ON

The run turned Windows Script Host on for the PostgreSQL installer. Then one of these happened:

- The run could not turn it off again.
- The installer is still running.

What the report shows:

- **Exit code** is at least `40`.
- **Run itself succeeded:** `IssueCode` is `WSH_LEFT_ON`.
- **Run failed:** `IssueCode` names that failure, and `ActionRequired` adds the Windows Script Host step.
- **Saved values** are in `WshOriginalValues` in the run's `recovery-state.json`.

What to do: when the installer has exited, run the command in `ActionRequired`, or run `-Recover` if the marker is still there.

This alert comes once. When no marker is left, later runs see only the live setting. So act on it the first time.

See [Windows Script Host and Veeam hardening](windows-script-host.md).

## The CHANGES-IN-PROGRESS marker

A `CHANGES-IN-PROGRESS.marker` file in the work root (see [Logs, backups and evidence](evidence.md)) blocks every normal audit/install. Those modes return exit `40`.

> [!WARNING]
> Do not delete the marker merely to make the next run proceed.

Use `-Recover` for an interrupted run (see the next section).

## Using -Recover

Use `-Recover` for an interrupted run.

### What it checks first

- **Trusted data:** it validates that the marker and versioned `recovery-state.json` resolve inside this work root and are trusted recovery data.
- **PowerShell module:** before it changes anything, it checks that the Veeam PowerShell module loads in this PowerShell. VBR 13 and VB365 need PowerShell 7.

If the module does not load:

- A pre-installer or NATS recovery stops with `RECOVERY_MODULE_UNAVAILABLE` (exit `40`) and changes nothing.
- Finishing an installed run stays diagnostic-only.

What to do: run `-Recover` again in PowerShell 7.

### Before the installer started

This applies if the recorded installer-started flag is false and the stage is `JOBS_DISABLED` or `SERVICES_STOPPED`.

- **Restores:** it restores and verifies captured PostgreSQL, NATS, Veeam service, and job state.
- **Success** returns exit `0` and removes the marker.

### After the installer started

Recovery finishes the run only when everything proves it safe:

- **PostgreSQL** answers at the recorded target version.
- **Installer** is no longer running.
- **Veeam services** are all still stopped.
- **Disabled-job record** is readable.

When all checks pass, it then:

- applies the mandatory Veeam tuning
- restores the captured service states
- re-enables the jobs (`RECOVERED_POSTINSTALL`, exit `0`)

After a successful finish (`RECOVERED_POSTINSTALL`) it does not report `RebootRequired=True`, so schedule the restart Veeam recommends through the RMM (see [Rebooting](running-from-an-rmm.md#rebooting)).

A tuning failure leaves Veeam down, as it does during `-Install`.

### Diagnostic-only

If the installer started or may have started and any of those checks fails, `-Recover` is **diagnostic-only** (`RECOVERY_DIAGNOSTIC_ONLY`):

- **No changes:** it changes no service, job or PostgreSQL state.
- **Windows Script Host:** it only turns Windows Script Host off again if the interrupted run left it on.
- **Failed check:** it names the check that failed.
- **Report:** it reports PostgreSQL/service state plus the actual recorded, unrestored job names.
- **Exit code:** `40` or `50`.
- **No rollback:** it does not roll back database files or blindly re-enable schedules.

### While it runs

- **Active work:** if active work appears during recovery, it waits naturally.
- **No forced stops:** no job or restore is forcibly stopped.
- **Veeam console:** an open Veeam console is closed once it is the only thing left blocking.
- **VB365 maintenance:** this applies if a VB365 maintenance start had an unknown client outcome.
  - The script never adopts or stops a time/scope-matched session whose ID was not returned by its own start call.
  - If such a session exists, it leaves schedules and the marker in place for an operator.

### Other rules

- **NATS:** for a NATS update run, see [NATS updates (VB365)](nats.md).
- **Not combinable:** `-Recover` cannot be combined with `-Install` or `-Reboot`.

## Marker could not be removed

This is when rollback/state restoration succeeds but the completed marker cannot be removed. The result is:

- exit `40`
- `Stage=COMPLETE`
- `IssueCode=MARKER_REMOVE_FAILED`

Jobs are not reported as disabled when their durable records say they were restored.

What to do: confirm the completed state, then remove the stale marker under the operator change record.

[Back to the README](../README.md) · [All docs](README.md)
