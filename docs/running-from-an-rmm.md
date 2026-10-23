# Running it from an RMM, and rebooting

This page covers how to deploy the script from an RMM and how restarts work after an update, so read it before you set up the RMM job.

**In short**

* **Run it locally and elevated** from an independent RMM agent or a Windows scheduled task. Do not launch it through the Veeam Management Agent or run it over WinRM / `Invoke-Command`.
* **Roll out in rings.** The script has no in-script version allow-list. Rollout rings in the RMM are the approval and canary mechanism.
* **Without `-Reboot`**, the script never restarts the server. On exit `6` or `8`, the RMM must reboot, verify `LastBootUpTime`, and rerun audit.
* **With `-Install -Reboot`**, a fully successful update books a Windows restart `-RebootDelaySeconds` later (default `120`). It normally returns exit `0` (or `7` on an EOL branch); the sections below list the exceptions.
* **No restart** after a failed, partial or rolled-back run, or when no update was needed.

## How to run it from an RMM

### Where to run it

**Use an independent RMM agent or Windows scheduled task** that runs locally and elevated.

Two things not to do:

* **Do not launch the install through the Veeam Management Agent.** Its Windows service name matches `Veeam*`, so the script deliberately disables and stops it during the maintenance. An unrelated RMM service whose service name does not match `Veeam*` is not touched.
* **Do not run it over WinRM / `Invoke-Command`.** The PostgreSQL installer is documented to fail under PSRemoting. The script blocks this when `-Install` is used.

### Give the run enough time

The whole update happens in the one run your RMM starts. That run can be long:

* **Waits for Veeam work:** each wait can last up to `jobWaitTimeoutMinutes` (default `720`, 12 hours), and one run can wait more than once.
* **Installer:** up to `installerTimeoutMinutes` more (default `120`).

Set your RMM's script timeout well above that, or lower `jobWaitTimeoutMinutes` (see [Parameters and settings](settings.md)). Do not set `installerTimeoutMinutes` below what the installer needs: a timed-out installer ends the run with exit `40`, Veeam stopped and jobs off. Keep patch restarts away from the server while `-Install` runs.

A run that is killed part-way, by an RMM timeout or a restart, does not finish its own clean-up. It can leave jobs disabled, Veeam services stopped and Windows Script Host on. The `CHANGES-IN-PROGRESS.marker` then makes every later audit and `-Install` return exit `40`. Run `-Recover` to finish or undo it. See [If it goes wrong](troubleshooting.md).

### Use the same WorkRoot every time

A run looks for an interrupted run's marker only in its own `-WorkRoot` (and in `C:\temp\VeeamPgUpdate`, the folder earlier versions used). Use the same `-WorkRoot` for every run on a server, `-Recover` included. Otherwise a later run cannot see the interrupted one.

### Suggested rollout

1. Run audit mode across the fleet and inventory exit codes `5`, `7`, `9`, and `11`.
2. Pilot each new PostgreSQL minor on one non-production VBR and one non-production VB365 server.
3. Promote through a small production ring and a soak period before the wider fleet.
4. Let the RMM act on the exit code:
   * Retry exit `10`.
   * Schedule reboots for `6`/`8` (or use `-Reboot`).
   * Create major-migration tickets for `7`/`8`/`9`.
   * Page immediately for `40`/`50`.

The script intentionally has no in-script version allow-list. Rollout rings in the RMM are the approval and canary mechanism for a newly published PostgreSQL minor.

What each code means: [Exit codes](exit-codes.md). All parameters: [Settings](settings.md).

### PowerShell version

PowerShell version matters:

* **VBR 13.1:** current documentation requires PowerShell 7.6.3.
* **VB365 8.6:** current documentation requires PowerShell 7.4.2+.

If the module will not load, the script **aborts** rather than assuming no jobs are running. On those servers, invoke `pwsh.exe` instead of `powershell.exe`.

## Rebooting

Veeam's KBs recommend restarting after the update.

A successful supported-branch update returns exit `6`; an EOL update returns exit `8`.

Without `-Reboot`, both report `Outcome=UPDATED_REBOOT_REQUIRED` and `RebootRequired=True`.

### Without `-Reboot`

Without `-Reboot` the script never restarts the server. The RMM must:

1. Reboot the server.
2. Verify `LastBootUpTime`.
3. Rerun audit.

**Do not rerun the installer** merely because exit `6` or `8` was returned.

After a verified reboot, audit returns:

* **`0`** on a supported branch.
* **`7`**, the persistent EOL result.
* **`5` (or `9`)** on VB365 instead, if the update run reported `NatsStatus=UPDATE_PENDING`. The [NATS update](nats.md) is still due, so schedule one more `-Install` run.

### With `-Install -Reboot`

After a fully successful update, the script books a Windows restart `-RebootDelaySeconds` later (default `120`). Booking the restart is its very last action.

The delay lets the run finish and the RMM collect its output before Windows restarts.

The run then returns:

* `Outcome=UPDATED_REBOOT_SCHEDULED`.
* Exit `0` (or `7` on an EOL branch).
* The restart time in `RebootScheduledAt`.

What to know next:

* **Cancel** a booked restart with `shutdown /a`.
* **Confirm** after the restart: rerun audit.
* **NATS-only update:** it needs no restart, so `-Reboot` books none.
* **NATS update still due:** if a PostgreSQL update booked a restart, the run returns exit `5` (or `9`) instead of `0` (or `7`). The RMM then schedules the next `-Install` run.

### Jobs that start inside the delay

> [!WARNING]
> Once schedules are back on, VBR has no barrier that stops new work. A job that starts inside the delay is interrupted by the restart.

To keep that window small, the script checks for Veeam work once more just before booking.

### When no restart is booked

The script books no restart if any of these happens:

* A job or restore has started.
* An Explorer is open.
* The last check for Veeam work, just before booking, fails.
* `shutdown.exe` cannot book the restart.

In those cases it reports `IssueCode=REBOOT_NOT_SCHEDULED`. It returns `Outcome=UPDATED_REBOOT_NOT_SCHEDULED` with exit `6` (or `8`), for the RMM to reboot.

An open Veeam console does not stop the restart.

**Windows Script Host still on:** the script also books no restart while Windows Script Host is still on. The end of that run tries once more to turn it off:

* **If that works:** exit `6` (or `8`) with `WshStatus=RESTORED`.
* **If not:** exit `40` with `WshStatus=LEFT_ON` and `IssueCode=WSH_LEFT_ON`.

See [Windows Script Host and Veeam hardening](windows-script-host.md).

**Never a restart:** the script never restarts after a failed, partial or rolled-back run, or when no update was needed.

[Back to the README](../README.md) · [All docs](README.md)
