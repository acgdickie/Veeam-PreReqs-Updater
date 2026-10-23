# Changelog

All notable changes, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The project has no version
numbers, so each entry is the date the change reached GitHub, with its commit IDs. When
you change a script, add your entry at the top.

## 2026-10-23

### Changed

* README rewritten as a short front page: what the script does, why it matters, whether it
  suits your server, the quick start and the exit codes come first. The full detail moved,
  without loss, to pages in [`docs/`](docs/README.md), and this changelog moved from the
  README to `CHANGELOG.md`.

### Fixed

* [NATS updates (VB365)](docs/nats.md) said the NATS update was built from Veeam's
  documentation, not from a live install. It has run on a live VB365 server, and the page
  now says so.

## 2026-10-22

### Fixed

* SAP HANA, Oracle RMAN and SAP on Oracle backup policies (`Get-VBRApplicationBackupJob`)
  could not be turned off safely. Their PowerShell object has no enabled property: its
  `ScheduleEnabled` stays True after `Disable-VBRApplicationBackupJob`. So the run stopped
  with `JOB_DISABLE_FAILED`, and the rollback skipped the policy it had just turned off,
  leaving it disabled while logging "re-enabled". The state is now read from Veeam's
  `CBackupJob` (`IsScheduleEnabled`), which follows the console; if that cannot be read,
  the run refuses before changing anything. Every rollback and recovery now switches back
  on any job the run tried to turn off, whatever its enabled flag says, and the log says
  "re-enabled" only when it really switched a job on. STEP 6B now names any application
  backup policy that is turned off, because an older version could leave one off.
* Three error messages built their list with `\"` inside `$( )`, which PowerShell runs as a
  command: the job list that stayed on after disabling, the open Veeam Explorers before
  shutdown, and the services that would not stop. The run still failed safely, but the
  summary showed a "not recognized" error instead of the names, and the last two ended as
  `UNHANDLED_ERROR` (exit `40`) instead of `VEEAM_UI_OPEN` (exit `10`) or
  `SERVICES_WONT_STOP` (exit `20`).

## 2026-10-21

### Changed

* Windows Script Host turned off by Veeam's hardening no longer stops the run. Before, it
  stopped at STEP 9 (`WSH_DISABLED`, exit `20`). Now `-Install` turns it on only while the
  PostgreSQL installer runs, then puts back the exact setting, as Veeam KB4699 describes. No
  restart is needed. See
  [Windows Script Host and Veeam hardening](docs/windows-script-host.md).

### Added

* Report field `WshStatus` (`ENABLED`, `DISABLED`, `RESTORED` or `LEFT_ON`).
* Outcome `WSH_NOT_WRITABLE` (exit `20`, at STEP 9, nothing changed): Windows Script Host
  is off and this account cannot change it.
* Outcome `WSH_ENABLE_FAILED` (exit `20`): Windows Script Host could not be turned on, so
  the installer never started and the run rolled back. Issue code `WSH_LEFT_ON` (exit `40`):
  it could not be turned off again.
* README: [Closing out an earlier run by hand](docs/troubleshooting.md#closing-out-an-earlier-run-by-hand), for a `VERIFIED` marker
  when the Veeam services already run.
* `-RemoveStaleVeeamOneRecord`: deletes a leftover `HKLM\SOFTWARE\Veeam\Veeam ONE` key that
  this run proved stale, after a verified `.reg` backup in the log folder, in an audit too.
  Report field `StaleVeeamOneRecord` (`present`, or `removed; backup <path>`). A failed
  removal is exit `20` (`STALE_VEEAM_ONE_RECORD_REMOVE_FAILED`).

### Fixed

* A server where Veeam ONE had been uninstalled was refused as `VEEAM_ONE_PRESENT` (exit
  `11`), because the uninstall left the `HKLM:\SOFTWARE\Veeam\Veeam ONE` key behind. Veeam
  ONE now counts as installed only with a Veeam ONE service or installed-programs entry as
  well. A key alone is logged as a leftover. If either list cannot be read, the server is
  still refused, as before.
* `-Recover` in a PowerShell the Veeam module cannot load in (for example Windows
  PowerShell 5.1 on VBR 13) could start the Veeam services and then fail to reach the jobs,
  leaving a run that `-Recover` then refused. It now checks the module first and changes
  nothing: `RECOVERY_MODULE_UNAVAILABLE` (exit `40`) for a pre-installer or NATS recovery,
  and `RECOVERY_DIAGNOSTIC_ONLY` for finishing an installed run.
* A run blocked by an earlier run's marker said "Veeam services are STOPPED and jobs are
  DISABLED" and named a backup folder that does not exist. It never checked either. It now
  names the earlier run (PostgreSQL or NATS), its stage and its folder (also in
  `RecoveryRunDir`), counts the Veeam services running now, and gives the next step for
  that stage. The whole marker goes to the log.

## 2026-10-20

### Added

* README: [In short](docs/how-it-works.md#in-short), a ten-line summary of the steps at the top of
  [What the script does, step by step](docs/how-it-works.md).

### Fixed

* The log line for Enterprise Manager beside VBR said that setup was "excluded". It now
  says it is supported, and says when it is not: Enterprise Manager without VBR.

## 2026-10-15

### Added

* README: [What the script does, step by step](docs/how-it-works.md), every
  step the script logs, with what it does and why. It replaces the shorter `-Install` list.
* README: this changelog.

## 2026-10-13

### Added

* NATS updates on VB365 servers, following Veeam KB4742 (`460339f`). Same 2.x line only,
  never another line and never older. One change per run: PostgreSQL first, NATS on the
  next `-Install` run. The run backs up the NATS service, config file and message store,
  verifies NATS and then VB365 on the new version, and puts the old version back on a
  failure. New report fields `NatsInstalled`, `NatsTarget`, `NatsStatus` and `NatsDetail`.
  New built-in setting `updateNats`. `-Recover` recovers an interrupted NATS update.
* The NATS supported list is read from Veeam's website on every run, and the download is
  checked against the SHA256 published with the NATS release, so a version Veeam adds
  needs no script change. The SHA256 built in for 2.10.28 and 2.12.8 must still agree
  (`HASH_CONFLICT`) (`a6eea4d`).
* `-Reboot` books a delayed Windows restart after a fully successful update, and
  `-RebootDelaySeconds` sets the delay (default 120 seconds) (`936d2eb`).

### Changed

* A stuck VB365 organisation sync gives a warning and fills `Vb365SyncStuck`, and the run
  carries on instead of waiting for it (`bc11a2d`).
* `NatsDetail` says what the run did with NATS, not only what the audit found (`3677568`).
* README brought up to date with the scripts: exit codes, report fields, stages, the
  `-Install` steps, Enterprise Manager rules and recovery (`ebdbe48`).

### Fixed

* An ended VB365 job session (`Disconnected`) and an organisation sync booked for later no
  longer block the wait for Veeam work (`15322ac`).
* VB365 maintenance mode: the run waits for the session to reach `Running` instead of
  giving up while it is still `Preparing` (`cf4ca2b`).
* NATS backup failed on a real VB365 8.6 server: `icacls` cannot read message-store paths
  longer than 260 characters. Only the store folder's permissions are saved now
  (`67ec48f`).
* A `-Recover` that saved its state and then failed left a marker the next `-Recover`
  refused. The marker now stays bound to the original run (`460339f`).

### Removed

* `Find-StuckVBMJobs.ps1`, a separate monitoring script added on this day (`dff6816`,
  `18fa748`, `570e2e1`), moved to its own repository,
  [acgdickie/Find-StuckVBMJobs](https://github.com/acgdickie/Find-StuckVBMJobs)
  (`50344dc`).

## 2026-10-12

### Added

* First public version (`96ac772`). Earlier development history is not published.
  * Audits, and with `-Install` applies, the latest PostgreSQL minor update on the same
    major version, on VBR 12 and 13 and on VB365 8.6 or later. Audit is the default and
    changes nothing.
  * Waits for Veeam work to finish, never kills a job or restore, closes an open Veeam
    console, disables and restores jobs, and holds VB365 in repository maintenance mode.
  * Backs up first: the VBR configuration backup (retried once after starting stopped
    automatic Veeam services), a dump of every Veeam database, and a cold copy of the data
    directory.
  * Verifies the installer's signature and the running version afterwards, and applies
    Veeam's mandatory PostgreSQL tuning.
  * Fails closed on anything it cannot prove, rolls back automatically before the
    installer starts, and recovers interrupted runs with `-Recover`.
  * Supports Enterprise Manager beside VBR. `-RemoveStaleEnterpriseManagerRecord` clears a
    leftover Enterprise Manager registry key, and the separate tool
    `Clear-StaleEnterpriseManagerRecord.ps1` checks and clears the leftover record inside
    the VBR database.
  * `Test-Helpers.ps1` tests the scripts on Windows PowerShell 5.1 and PowerShell 7.
