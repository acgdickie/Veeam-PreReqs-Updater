# Parameters and settings

This page covers the script's parameters, built-in settings and PostgreSQL target choice; read it before you set up an RMM policy or change a setting.

**In short**

- **`-Install`** actually does the update. Without it, the run is audit only.
- **No maintenance window**: `-Install` means "go now". Your RMM owns the window, retries and post-reboot verification.
- **Settings** live only inside the script. There is no `-ConfigPath` parameter and no external settings file.
- **PostgreSQL target** is not a setting. The script selects the latest published minor of the installed branch, and never downgrades.
- **Veeam tuning** is mandatory after every successful minor update. There is no setting to skip it.

## Parameters

| Parameter | Default | What it does |
|---|---|---|
| `-Install` | off | Actually do the update. Without it, audit only |
| `-Reboot` | off | With `-Install`: after a fully successful update, book a Windows restart `-RebootDelaySeconds` later. See [Rebooting](running-from-an-rmm.md#rebooting) |
| `-RebootDelaySeconds` | `120` | Seconds from booking the restart to Windows restarting, 30 to 3600. Only used with `-Reboot` |
| `-Recover` | off | Restore captured state from an interrupted run. Details below |
| `-WorkRoot` | `C:\ProgramData\VeeamPgUpdate` | Protected logs and recovery evidence, including dumps and the cold copy. Use the same value for every run on a server: a run sees an interrupted run's marker only in its own WorkRoot (and in the former default `C:\temp\VeeamPgUpdate`) |
| `-SkipDownloadInAudit` | off | Skip the EnterpriseDB installer-availability check. Details below |
| `-RemoveStaleEnterpriseManagerRecord` | off | Delete a proven-stale `Veeam Backup Reporting` registry key. Details below |
| `-RemoveStaleVeeamOneRecord` | off | Delete a proven-stale `HKLM\SOFTWARE\Veeam\Veeam ONE` registry key. Details below |

### No maintenance window

> [!IMPORTANT]
> There is no maintenance window. `-Install` means "go now". It runs when you run the RMM script or policy.

The independent RMM owns:

- the maintenance window;
- retries;
- the reboot, unless `-Reboot` is used;
- post-reboot verification.

### `-Recover` runs on its own

- **Restore**: `-Recover` restores captured state from an interrupted run.
- **Finish**: if the installer finished and PostgreSQL proves healthy at the target version, `-Recover` finishes the run.
- **Separate operation**: `-Recover` cannot be combined with `-Install` or `-Reboot`.

### `-SkipDownloadInAudit`

This switch skips the EnterpriseDB installer-availability check. The audit still contacts:

- PostgreSQL's version feed.
- Veeam's help center, on VB365.
- GitHub, on VB365, when a NATS update is due.

### Stale registry record switches

`-RemoveStaleEnterpriseManagerRecord` and `-RemoveStaleVeeamOneRecord` work the same way:

- **Proven-stale only**: each deletes its registry key only when the key is proven stale.
- **Backup first**: each exports and verifies a `.reg` backup into the `logs` folder before it deletes.
- **Audit runs**: each works in an audit run too, without `-Install`.
- **Failure**: a failed removal is exit `20`.

| Switch | Registry key | Report field | Failed removal |
|---|---|---|---|
| `-RemoveStaleEnterpriseManagerRecord` | `Veeam Backup Reporting` | `StaleEmRecord` | exit `20` (`STALE_EM_RECORD_REMOVE_FAILED`) |
| `-RemoveStaleVeeamOneRecord` | `HKLM\SOFTWARE\Veeam\Veeam ONE` | `StaleVeeamOneRecord` | exit `20` (`STALE_VEEAM_ONE_RECORD_REMOVE_FAILED`) |

For the Veeam ONE key, proven stale means no Veeam ONE service and no Veeam ONE installed program. For leftover Enterprise Manager records, see [Leftover Enterprise Manager records](enterprise-manager.md).

## Built-in settings

The configurable settings live **only inside the script**:

- **Location**: near the top, under the banner `BUILT-IN SETTINGS`.
- **Values**: the JSON block in `Get-DefaultConfig`, a few lines below the banner.

To change a setting:

1. Edit it there.
2. Review the change.
3. Re-upload the script to your RMM.

There is no `-ConfigPath` parameter. No external settings file is read.

| Setting | Default | Allowed values | What it does |
|---|---|---|---|
| `jobWaitTimeoutMinutes` | `720` | 1 to 10080 | Maximum time each wait gives active Veeam work to finish naturally |
| `installerTimeoutMinutes` | `120` | 1 to 10080 | Maximum unattended wait for the EnterpriseDB installer |
| `retentionDays` | `30` | 1 or more (a value below 1 is treated as `30`) | Minimum age before completed logs and recovery sets become eligible for deletion |
| `updateNats` | `true` | `true` or `false` | VB365 only. Whether `-Install` updates NATS when an update is due |

Invalid timeout values:

- **`jobWaitTimeoutMinutes`**: any value other than 1 to 10080 stops `-Install` with exit `20` (`BAD_JOB_WAIT_TIMEOUT`) before anything changes.
- **`installerTimeoutMinutes`**: any value other than 1 to 10080 stops a PostgreSQL update with exit `20` (`BAD_INSTALLER_TIMEOUT`) before anything changes.

### `updateNats`

This setting applies to VB365 only. See [Updating NATS (VB365)](nats.md).

- **`true`**: `-Install` updates NATS when a same-line update is due, on a run where PostgreSQL needs nothing.
- **`false`**: a due NATS update is only reported (`NatsStatus=UPDATES_OFF`).
- **Both due**: when PostgreSQL and NATS are both due, that run updates PostgreSQL. The next `-Install` run updates NATS.

## How the PostgreSQL target is chosen

The PostgreSQL target is **not** a maintained setting. On every default run, the script:

1. reads the running server's version with `SHOW server_version_num`;
2. finds that exact branch in
   [`postgresql.org/versions.json`](https://www.postgresql.org/versions.json);
3. selects its latest published minor; and
4. verifies that the target is still on the installed branch before doing anything.

Examples:

- **15.2** targets the latest 15.x.
- **17.3** targets the latest 17.x.
- **A future installed branch** works the same way, without adding it to the script.

### When the target is limited

- **Feed problem**: if PostgreSQL's version feed is unavailable, missing the branch, duplicated, or malformed, the script fails closed.
- **End-of-life branch**: the script targets the final published minor. It continues to return an EOL code until the server is migrated to a supported major. See [Exit codes](exit-codes.md).
- **Already current**: if the installed version is already equal to or newer than the target, the script never downgrades PostgreSQL.

## `jobWaitTimeoutMinutes`

The script polls until all detected Veeam work of these kinds is idle:

- backup
- copy
- restore
- CDP
- tape
- agent
- plug-in
- configuration
- protection-group
- VB365 repository
- VB365 organization-cache synchronization

How the wait behaves:

- **No stopping**: the script never calls a stop-job cmdlet.
- **Per wait**: the setting is the maximum time for each wait. One run can wait more than once.
- **Timeout before the outage**: exit `10` tells the RMM to retry.
- **Timeout after the update**: work still running when schedules are due to be re-enabled is exit `40` (`FINAL_JOB_DRAIN_TIMEOUT`) instead. The schedules stay disabled.

## `installerTimeoutMinutes`

This setting bounds how long the RMM run waits for the unattended installer. When the timeout expires:

- **Installer**: not forcibly killed, because it may be changing binaries.
- **Marker**: remains.
- **Schedules**: remain disabled.
- **Exit `40`**: the run ends with exit `40`, which pages an operator.

## Mandatory Veeam tuning

There is no setting to skip tuning. It runs in two parts.

1. **Before the installer**: the script runs the product-appropriate command for the server's CPU and RAM. This happens while the Veeam control service is still available but schedules are disabled. The command is `Set-VBRPSQLDatabaseServerLimits` or `Set-VBOPSQLDatabaseServerLimits`. The script saves its generated SQL.
2. **After the minor update**: the script applies that exact SQL, restarts PostgreSQL, and verifies the target version is queryable.

| Failure | Exit |
|---|---|
| Failure at the pre-installer point | `20`, with safe rollback |
| SQL application/tuning failure | `40` |
| PostgreSQL down or unqueryable | `50` |

## `retentionDays`

`retentionDays` is not only for script logs. It covers transcript logs and completed recovery sets.

| Recovery set | Contents |
|---|---|
| PostgreSQL run | Database dumps, roles, configuration copies, the cold data-directory copy, service/job state, tuning and installer logs |
| NATS run | Service/job state, the NATS service's registry key, its config file (which holds the NATS credentials), and a copy of the message store |

What is kept:

- **Unresolved runs** are retained regardless of age.
- **The two newest completed recovery sets** are retained regardless of age.
- **Older completed sets** become eligible for deletion after `retentionDays`.

Copy recovery evidence off-host if your operational policy requires protection from loss of the Veeam server itself. See [Where the evidence lives](evidence.md).

## Removed settings

### Target allow-lists

The former `approvedTargets`, `supportedBranches`, and `branchFloors` settings have been removed.

- **Automatic**: new PostgreSQL minors are therefore selected automatically.
- **No allow-list**: new minors are no longer held for a manual allow-list edit.
- **Your check**: review PostgreSQL release notes and pilot normal RMM rollout.
- **Why**: an unusual minor release can still require a follow-up action such as `REINDEX`.

### Operator switches

The removed settings also include `abortIfVeeamOnePresent`, `abortIfRemoteVb365Proxies`, and `reapplyTuning`. Those behaviours are no longer operator switches:

- **Topology**: the initial topology exclusions fail closed.
- **Tuning**: Veeam PostgreSQL tuning is mandatory after every successful minor update.

[Back to the README](../README.md) · [All docs](README.md)
