# How it works

This page explains each step of a run and how the script handles Veeam jobs, restores and services, so you can match a log to a step.

## In short

1. **Checks it is safe to start.** Proves its work folder can be trusted, makes sure no
   other copy is running, and checks the server: Windows, run as administrator, and not
   part-way through an earlier run.
2. **Finds out what is installed.** Which Veeam product (VBR or VB365), where its database
   is (one local PostgreSQL), and which PostgreSQL version is running. Stops on any setup
   it does not support.
3. **Works out what is due.** The latest PostgreSQL minor release on the same major
   version, and on VB365 a NATS update on the same line. An **audit stops here** and
   reports.
4. **Waits for Veeam to be quiet.** Lets running backups and restores finish. It never
   stops one.
5. **Downloads and checks the update.** The PostgreSQL installer must be signed by
   EnterpriseDB. The NATS download must match its SHA256.
6. **Turns off the jobs.** Records and disables every scheduled job, and on VB365 puts the
   repositories into maintenance mode, so no new work starts.
7. **Backs up.** The VBR configuration backup and a dump of every Veeam database, then,
   with the services stopped, a full copy of PostgreSQL's data folder. For NATS: its
   service settings, config file and message store.
8. **Updates.** Stops the Veeam services and installs the PostgreSQL update, or switches
   NATS to the new version. One change per run: PostgreSQL first, NATS on the next run.
   If Veeam's hardening turned Windows Script Host off, it is on only while the
   PostgreSQL installer runs.
9. **Checks it worked.** Confirms the new version, applies Veeam's PostgreSQL tuning, and
   starts the Veeam services again.
10. **Turns the jobs back on** and reports the result for the RMM. After a PostgreSQL
    update the server needs a restart, by the RMM or with `-Reboot` (see
    [Rebooting](running-from-an-rmm.md#rebooting)).

If anything fails before the update itself, the script puts everything back the way it
was. If a run is interrupted, `-Recover` finishes it or puts it back.

## In detail

Every run writes each step to its log under the name in the first column, so you can match
a log to this list.

- An **audit** (no switch) runs the start-up steps and STEPs 1 to 10, then stops. It
  changes nothing.
- **`-Install`** carries on with STEPs 11 to 21 when PostgreSQL needs an update.
- **NATS path:** when PostgreSQL needs nothing and a NATS update is due on VB365,
  `-Install` takes the NATS path (`NATS 1/7` to `7/7`) after STEP 8 instead.
- **`-Recover`** stops at STEP 2 and recovers the interrupted run.

A step that finds a problem stops the run there with the exit code and `Outcome` shown in
the RMM summary. See [Exit codes](exit-codes.md) and [If it goes wrong](troubleshooting.md).

### Start-up (every run)

| Step | What it does | Why |
|---|---|---|
| Path check | Checks that `-WorkRoot` is an absolute path on a local drive and not a drive root. | The WorkRoot will hold the installer, dumps and recovery state. A bad path stops the run before anything is written (`WORKROOT_UNSAFE`, exit `20`). |
| Former WorkRoot | Looks for a changes-in-progress marker in `C:\temp\VeeamPgUpdate`, the folder earlier versions used. | An interrupted run there must be recovered first, not hidden (`LEGACY_WORKROOT_RECOVERY_REQUIRED`, exit `40`). |
| WorkRoot check | Creates the WorkRoot, or proves the existing one is the script's own: owner, ACL locked to SYSTEM and Administrators, the `.veeam-pg-updater` sentinel, and no junctions. Then starts the log (transcript). | A folder someone else can change could be used to swap files the script later runs or restores. Nothing is written to a folder that fails. |
| Single-instance lock | Takes the machine-wide lock `Global\VeeamPgUpdate`. | Two runs at once would fight over the same services and jobs. The second one stops (`CONCURRENT_RUN`, exit `10`). |

### Checks (audit and `-Install`)

| Step | What it does | Why |
|---|---|---|
| STEP 1 - Load settings | Loads the settings built into the script, then purges logs and completed run folders older than `retentionDays`. It keeps unresolved runs and the two newest completed recovery sets. | Settings come only from the reviewed script. Without the purge, daily audits would fill the disk. |
| STEP 2 - Context checks | Checks the switch combination, that the server runs Windows and is not a Veeam appliance, that the run is elevated, and that `-Install` is not over PowerShell remoting. Acts on a changes-in-progress marker (see below). | Each of these breaks an unattended update. An interrupted run must be dealt with before a new one starts. |
| STEP 3 - Detect Veeam products | Finds VBR, VB365, Veeam ONE and Enterprise Manager, and leftover registry keys (see below). Warns about Veeam services set to start automatically that are stopped. Refuses topologies outside the supported profile. | Decides which product profile applies, and stops early on a server the script does not support. |
| STEP 4 - Confirm database engine | Reads where each product keeps its database: VBR's active engine and connection from the registry, Enterprise Manager's database the same way, and VB365's `Config.xml` and `Proxy.xml`. All must be local PostgreSQL on one port. | Nothing is guessed. A remote database or two ports means the script cannot tell what it is updating. |
| STEP 5 - Detect PostgreSQL installation | Requires exactly one PostgreSQL installation in the registry and one PostgreSQL Windows service, which must run `pg_ctl.exe` or `postgres.exe` from that installation. Checks that `psql`, `pg_dump`, `pg_dumpall` and `pg_restore` are there. | The installer must patch the instance Veeam really uses, and the backup tools must exist. |
| STEP 6 - Read running server version | Requires PostgreSQL to be running, logs in, and reads the running version. Checks the instance in several ways (see below). | Proves the instance is the right one, standalone, and reachable, before anything else. |
| STEP 6B - Validate Veeam scheduling, activity and topology APIs | Loads the Veeam PowerShell module and runs four checks (see below). | An audit must prove the same things an install relies on, so a server reported as fine really is safe to update. |
| STEP 6C - Check NATS (VB365 only) | Read-only. Reads the `nats-server` service, its version, config file and message store, VB365's connection to it, Veeam's supported NATS list, and the package SHA256. Fills `NatsInstalled`, `NatsTarget`, `NatsStatus` and `NatsDetail`. | Decides whether a same-line NATS update is due, and whether it can be done safely. Any doubt leaves NATS alone. |
| STEP 7 - Resolve target version | Reads `postgresql.org/versions.json` and picks the latest minor on the running branch. Flags an end-of-life branch. Blocks any major-version change. | Always the newest fixes, never an upgrade. A feed that cannot be read stops the run instead of guessing. |
| STEP 8 - Idempotency gate | When PostgreSQL is already current or newer, the run ends here: `ALREADY_CURRENT` or `LOCAL_VERSION_AHEAD`. If a NATS update is due instead, an audit reports it (exit `5` or `9`), and `-Install` takes the NATS path. | Never downgrades, never repeats work, and makes one change per run. |
| STEP 9 - Environment pre-flight | Checks Windows Script Host, pgAdmin and free disk space (see below). | pgAdmin and low disk space are known causes of a failed unattended install. Windows Script Host is handled in STEP 17: see [Windows Script Host and Veeam hardening](windows-script-host.md). |
| STEP 10 - Resolve installer URL | Finds the exact Windows x64 installer on EnterpriseDB's file host, then on its download page. An audit skips this with `-SkipDownloadInAudit`. | An installer not published yet is reported (exit `10`, or `7` on an EOL branch) rather than run later from a guessed link. |
| Audit stops here | Reports the update that is due (exit `5`, or `9` on an EOL branch). | Audit never changes anything. |

#### STEP 2 detail

- **Marker found:** a changes-in-progress marker sends `-Recover` to recovery and stops
  every other run (`PRIOR_RUN_INCOMPLETE`, exit `40`).
- **No marker:** `-Recover` ends here (`RECOVERY_NOT_NEEDED`, exit `0`).

#### STEP 3 detail

- **Veeam ONE** is found by its registry key plus a Veeam ONE service or installed program.
  The key alone is a leftover, removed with `-RemoveStaleVeeamOneRecord`.
- **Enterprise Manager:** a leftover Enterprise Manager registry key is found too.
  `-RemoveStaleEnterpriseManagerRecord` removes it. See
  [Enterprise Manager and leftover records](enterprise-manager.md).

#### STEP 6 detail

- **Login:** logs in as `postgres` (Windows SSPI), naming the cause if the login is refused.
- **Data directory:** proves the data directory on Veeam's port is the registry's.
- **WorkRoot:** keeps `WorkRoot` outside the data directory.
- **Pooler or port:** checks for a pooler or port mismatch.
- **Databases:** lists the databases.
- **Standalone only:** refuses replication, standby or Windows Failover Clustering.

#### STEP 6B detail

- **Job families:** lists every job and policy family it can safely turn off and back on.
- **VB365:** checks the 8.6 maintenance-mode commands and that every proxy is local.
- **Activity:** reads current Veeam activity.
- **Major version:** checks the registry and the running server agree on the major version.

#### STEP 9 detail

- **Windows Script Host:** reports whether it is turned off (`WshStatus=DISABLED`). This
  does not stop the run.
- **Write access:** if Windows Script Host is off, checks that this account can change it.
  If not, the run stops (`WSH_NOT_WRITABLE`, exit `20`, nothing changed).
- **pgAdmin:** checks that pgAdmin is not running.
- **Disk space:** checks that the WorkRoot drive has 400 MB plus twice the data directory
  plus 1 GB free.

### PostgreSQL update (`-Install` only)

| Step | What it does | Why |
|---|---|---|
| STEP 11 - Inventory schedules and wait for jobs/restores to finish naturally | Repeats the STEP 6B checks, checks the timeout settings, then waits for running jobs and restores to finish. Closes an open Veeam console once it is the only thing left. | No backup or restore is ever killed. A timeout returns exit `10` for a later retry. |
| STEP 12 - Download and verify the installer | Downloads the installer, checks its length, and requires a valid Authenticode signature from EnterpriseDB. | Only a genuine installer is run. Any failure is exit `30` with nothing changed. |
| STEP 13 - Disable scheduled jobs | Records every enabled job, then disables each one and checks it (see below). | Nothing new starts during the outage, and recovery knows exactly which jobs to turn back on. The tuning SQL needs the Veeam services, which stop next. |
| STEP 14 - Backups | Runs the VBR configuration backup and judges it (retrying once after starting stopped automatic Veeam services). Then backs up more (see below). | A restore path that does not depend on the update working. |
| STEP 15 - Disable and stop all Veeam services | Records every Veeam service's startup type and state, then disables and stops them (VB365 Proxy and Service first, the Management Agent last), then NATS (see below). | The update and the cold copy need PostgreSQL offline with no one using it. |
| STEP 16 - Cold copy of the PostgreSQL data directory | Saves the data directory's permissions, copies the whole stopped data directory, and checks the copy file count and size. | A complete file-level copy to restore from if the installer breaks PostgreSQL. |
| STEP 17 - Run the PostgreSQL installer | Runs the PostgreSQL installer unattended. Turns Windows Script Host on for it if it is off (see below). | The update itself. Once the installer starts, automatic rollback is not allowed: only an operator decides. The installer fails part-way without Windows Script Host (Veeam KB4698). |
| STEP 18 - Verify the update | Starts PostgreSQL if needed and requires it to report the target version. Compares the `.conf` files with the copies from STEP 14. | The installer's exit code alone is never trusted. |
| STEP 19 - Apply mandatory Veeam PostgreSQL tuning | Applies the tuning SQL from STEP 13, restarts PostgreSQL, and checks it is back at the target version. | Veeam requires its tuning. If it fails, Veeam stays down and jobs stay off for an operator. |
| STEP 20 - Restore Veeam service state | Puts back every startup type and starts NATS and every service that was running, in dependency order. Waits 90 seconds, then checks every service, PostgreSQL, the broker port 9501 (VBR only), and the Veeam PowerShell connection. | Veeam must be healthy before any job runs again. |
| STEP 21 - Re-enable jobs and finish | Ends VB365 maintenance mode, waits for any new work, turns every recorded job back on, removes the changes-in-progress marker, and deletes the installer. Returns exit `6` (or `8`), or with `-Reboot` books the restart. | Leaves the server as it was, on the new version, with a clear result for the RMM. |

#### STEP 13 detail

After the jobs are disabled:

1. Waits again for work that started in the meantime.
2. On VB365, puts every repository into maintenance mode and waits until it is Running.
3. Generates the mandatory Veeam tuning SQL.

#### STEP 14 detail

1. On VB365, copies `Config.xml` and `Proxy.xml`.
2. Dumps every Veeam database and the roles, and checks each dump.
3. Copies the four `.conf` files.

#### STEP 15 detail

After the services and NATS are stopped:

1. Checks nothing else is connected to PostgreSQL.
2. Dumps any cache database VB365 created meanwhile.
3. Stops PostgreSQL.

#### STEP 17 detail

1. If Windows Script Host is turned off, records its exact setting and turns it on
   (Veeam KB4699).
2. Records that the installer is starting.
3. Runs the installer unattended with a bounded wait. A timed-out installer is never
   killed.
4. Collects the installer's logs.
5. Turns Windows Script Host off again, whatever the result (`WshStatus=RESTORED`).

### NATS update (`-Install` on VB365, when PostgreSQL needs nothing)

| Step | What it does | Why |
|---|---|---|
| NATS 1/7 - Download and check NATS | Downloads the release, checks its SHA256, extracts only `nats-server.exe`, runs its version and config checks, and checks free disk space. | Everything that can fail without an outage is tested first. |
| NATS 2/7 - Wait for Veeam work, disable jobs, start VB365 maintenance mode | As STEPs 11 and 13. | No work runs while NATS is changed. |
| NATS 3/7 - Stop Veeam services and NATS | As STEP 15, but PostgreSQL keeps running. | VB365 must not use NATS while it is switched. |
| NATS 4/7 - Back up the NATS service, config file and message store | Saves the service's registry key, the config file, the store folder's permissions and a checked copy of the store. | Everything needed to put the old NATS back. |
| NATS 5/7 - Point nats-server at NATS | Copies the new program into a new version folder beside the old one, and switches the service to it through the Windows service manager. | The change itself, following Veeam KB4742. The old folder stays. |
| NATS 6/7 - Start NATS, then VB365, and verify | Starts NATS alone and checks its version, then starts VB365 and checks every service, PostgreSQL, and that VB365 connects again. | Proves VB365 works on the new version. A failure puts the old version back. |
| NATS 7/7 - Re-enable jobs and finish | Ends maintenance mode, waits for any new work, and turns the jobs back on. Returns exit `0` (or `7`). | No restart is needed after a NATS update. |

[NATS updates (VB365)](nats.md) has the full detail and the rollback rules.

### `-Recover`

| Step | What it does | Why |
|---|---|---|
| Recovery (from STEP 2) | Checks the run's own records and the Veeam module, then finishes or undoes the interrupted run, depending on how far it got (see below). | Finishes or undoes an interrupted run from its own records, never by guessing. |

Before anything changes, recovery checks that:

- the marker and its recovery state are the script's own and belong together
- the Veeam module loads in this PowerShell

Then, depending on how far the run got:

- **Installer not started:** puts back captured job and service state.
- **Installer finished and PostgreSQL proven healthy at the target version:** finishes the
  run.
- **NATS run:** puts the old NATS back, or finishes a NATS update.
- **Anything less certain:** only reports.

In every case, if the interrupted run left Windows Script Host turned on and the installer
is no longer running, recovery turns it off again.

### When a run ends

| Step | What it does | Why |
|---|---|---|
| Windows Script Host | If the run turned Windows Script Host on and it is still on (for example, the run stopped in STEP 17), turns it off again with its exact old setting (see below). | A hardened server does not stay less hardened. |
| ROLLBACK | Only after a failure before the installer started (or, on a NATS run, before VB365 was verified on the new version). See below. | A failed run leaves the server as it found it. If that does not fully work, the run returns exit `40`. |
| RMM SUMMARY | Prints the one-line summary and writes `last-result.json` (and `result.json` in the run folder), then releases the lock and exits with the exit code. | The RMM reads the result. See [Exit codes](exit-codes.md). |

#### Windows Script Host detail

- **Installer still running:** not while the PostgreSQL installer is still running. It
  would fail part-way.
- **Cannot turn it off:** the run returns exit `40` with `WshStatus=LEFT_ON`, and
  `ActionRequired` gives the command.

#### ROLLBACK detail

- **Old NATS:** on a NATS run, puts the old NATS back.
- **Services:** starts PostgreSQL, NATS and the Veeam services as they were.
- **Maintenance mode:** ends VB365 maintenance mode.
- **Jobs:** turns the jobs back on.
- **Marker:** removes the marker.

## Job and restore handling

### What is checked

Audit and install modes both inventory every job family the script knows how to
round-trip. They also check the corresponding job/restore/session APIs. Both happen before
an audit can report the server current.

The run fails closed if:

- a required API is missing
- a query fails
- an enabled-state property is unknown
- a job cannot be identified and later re-enabled by stable ID

The one exception is a feature the Veeam licence edition does not include (for example
application backup jobs below Enterprise Plus). Veeam refuses the query, so that family
cannot have jobs. The run logs a warning and treats it as empty.

Protection-group rescans and their agent deployment work are checked through current and
legacy VBR discovery-session types.

### VB365 organization syncs

VB365 whole-organization synchronization is also a fail-closed activity barrier. So is
each of its parts: Users, Groups, GroupMembers, Sites, and Mailboxes. They are barriers
because they write the PostgreSQL-backed organization cache.

| Sync state | Holds the run? |
|---|---|
| Only `Queued` for a later time | No. This is VB365's normal state between its daily syncs. |
| Running | Yes |
| Overdue by up to an hour | Yes |
| Due within 15 minutes | Yes |
| No readable time | Yes |
| Overdue by more than an hour and never started | No. It is stuck, not running. |

For a stuck sync, the run warns, names it in `Vb365SyncStuck`, and does not wait for it.

A VB365 job session that ended as `Disconnected` does not count as running, because VB365
never resumes it.

### Waiting for work to finish

If work is active, the script waits for it to finish naturally for up to
`jobWaitTimeoutMinutes` (see [Settings](settings.md)).

It does **not** forcibly stop or terminate backups, restores, copies, CDP sessions, tape
work, agent jobs, plug-in jobs, or VB365 operations.

Once idle, the script:

1. Disables every enabled managed schedule.
2. Durably records each change.
3. Verifies the disabled state.
4. Checks activity again before stopping services.

A race that starts new work causes a safe rollback/retry rather than termination.

### Remote manual starts

> [!IMPORTANT]
> The RMM maintenance policy must also prevent remote administrators from manually
> starting new VBR work during `-Install`.

VBR has no public atomic global new-work barrier. The script:

- disables every known schedule
- repeatedly refreshes schedule/activity state
- closes any open local VBR or VB365 console
- blocks on Veeam Explorer processes

But only an external change freeze closes the remote manual-start race completely.

### Open consoles

An open console is not waited for. The VBR console (`Veeam.Backup.Shell`) and the VB365
console (`Veeam.Archiver.Shell`) are clients only.

- **When:** `-Install` and `-Recover` close them once a console is the only thing left
  blocking. While a job still runs, the console is left alone.
- **How:** the script asks first, then forces. Run from an RMM as SYSTEM, the forced close
  is the normal path.
- **Unsaved work:** anything unsaved in that console is lost.
- **Veeam's procedure:** KB2991 also closes the console before stopping services.
- **Audit:** an audit run closes nothing.

### Open Veeam Explorers

A Veeam Explorer is never closed, because it runs its own item-level restore. An open
Explorer counts as active work.

The run waits up to `jobWaitTimeoutMinutes` for it to close, then exits `10` as
`JOB_WAIT_TIMEOUT`. Other cases:

- **Opens at a later check:** exit `10` as `JOB_DRAIN_TIMEOUT`, `FINAL_JOB_DRAIN_TIMEOUT`
  or `LAST_CHANCE_JOB_DRAIN_TIMEOUT`.
- **Opens just before services stop:** exit `10` at once, as `LAST_CHANCE_ACTIVITY_RACE`.

In each case, the Explorer is listed in `Detail` as `UI:<process>:PID<id>`.

After the update:

- **Re-enabling schedules:** an Explorer still open when schedules are due to be
  re-enabled is exit `40` (`FINAL_JOB_DRAIN_TIMEOUT`), and the schedules stay disabled.
- **During `-Recover`:** it is exit `40` (`RECOVERY_INCOMPLETE`).

`VEEAM_UI_OPEN` covers only an Explorer, or a console that could not be closed, found by
the last process check right before service shutdown.

### VB365 repository maintenance mode

For VB365, the script also places every repository into repository maintenance mode
without `-ForceStopSessions`.

- **Version:** that API was added in VB365 8.6.
- **Older builds:** an older VB365 build cannot provide the required new-work barrier, and
  therefore fails closed before changes.
- **Release:** the maintenance session is released only after services are healthy and the
  PowerShell connection has been re-established.

### Turning schedules back on

After PostgreSQL, mandatory tuning, and all required service health checks succeed, the
script re-enables and verifies exactly the schedules it disabled.

- **Already disabled:** schedules that were already disabled remain disabled.
- **Unhealthy:** if PostgreSQL, tuning, or a critical service is unhealthy, schedules
  remain disabled. Exit `40`/`50` includes their names and the required RMM action.

## Veeam service handling

### Stopping the services

Immediately before shutdown, the script:

1. Enumerates every Windows service whose **service Name** matches `Veeam*`.
2. Records each service's running state and exact startup type in
   `veeam-service-state.json`, before changing anything. The startup type is `Automatic`,
   `AutomaticDelayedStart`, `Manual`, or `Disabled`.
3. Sets every captured service to `Disabled` and stops it, including the Veeam Management
   Agent.

Stop order:

- **VB365 services** retain their required stop order.
- **Management-agent services** are stopped last.

### Starting them again

After PostgreSQL is healthy, or during a pre-installer rollback, the script:

- restores each captured service's exact startup type
- starts every service that was running at the start

It never stops a formerly stopped service that has since become running. That service may
now own newly-arrived manual work. This conservative state drift is logged, while its
startup type is still restored.

### What it leaves alone

- **Name match only:** the match is deliberately limited to the Windows service Name
  pattern `Veeam*`. It does not disable unrelated RMM or management services.
- **Dependency check:** before shutdown, the script also checks service dependencies. It
  aborts if the shutdown would cascade into a running service outside the planned
  `Veeam*`/NATS/PostgreSQL set.

> [!IMPORTANT]
> Because the script stops every `Veeam*` service, including the Veeam Management Agent,
> the install must be launched by an independent RMM agent or scheduler, not by the Veeam
> Management Agent.

### Other PostgreSQL clients

After Veeam is stopped, the script queries `pg_stat_activity`. It refuses to stop
PostgreSQL while any other client session remains.

- **Result:** it reports exit `10` and the client details for the RMM.
- **Never kills:** it never terminates those sessions.

[Back to the README](../README.md) · [All docs](README.md)
