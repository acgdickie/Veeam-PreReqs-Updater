# Exit codes and report fields

Read this page when you set up RMM alerting or read a result: it lists the exit codes, report fields and `Stage` values that a run returns.

**In short**

- **Exit code** is the RMM contract. Point RMM automation and alerting at the exact values in the table below.
- **Exit `40` and `50`**: page an operator.
- **Failure codes** `20`–`50` take precedence over informational EOL/reboot codes.
- **NATS left alone** does not show in the exit code: it follows PostgreSQL. Alert on `NatsStatus` too.
- **Final state record**: always use `Stage`, `JobsLeftDisabled`, and `ActionRequired`.

## Exit codes

The process exit code is the RMM contract. Point RMM automation and alerting at these exact values:

| Code | Meaning | Action |
|---|---|---|
| `0` | Healthy, with no outstanding RMM action. Also returned for the named outcomes listed under this table | None. After a booked restart, rerun audit to confirm |
| `5` | Supported branch: audit found a PostgreSQL minor update or a NATS update. One more case: see below | Schedule `-Install` through the rollout ring |
| `6` | Supported branch: update succeeded; reboot required | Schedule and verify a reboot |
| `7` | PostgreSQL branch is EOL | Open or maintain a major-version migration ticket |
| `8` | EOL branch and reboot required | Schedule a reboot and maintain the migration ticket |
| `9` | EOL branch, and a PostgreSQL minor update or a NATS update available | Schedule `-Install` and maintain the migration ticket |
| `10` | Safe transient condition: see the examples below | Retry later; no backup or restore was forcibly stopped |
| `11` | Unsupported or excluded topology | Handle manually; do not repeatedly retry as a transient failure |
| `20` | Pre-flight failed, or a NATS update failed and the old NATS was put back (`NATS_UPDATE_FAILED`) | Investigate before retrying |
| `30` | EnterpriseDB page, download, size, or signature check failed, or the NATS download or its SHA256 check failed | Investigate the download path; nothing was installed |
| `40` | **Post-change failure, unhealthy service, mandatory tuning failure, recovery needs an operator, or Windows Script Host was left turned on (`WshStatus=LEFT_ON`)** | **Page an operator and read the RMM issue fields** |
| `50` | **PostgreSQL is missing, down, unqueryable, or reports the wrong version after change/tuning/recovery diagnosis** | **Page an operator immediately and use the recovery evidence** |

### Other outcomes that return exit 0

- **`NOT_APPLICABLE`**: no detected Veeam product uses a local PostgreSQL database, for example VBR on Microsoft SQL Server.
- **`NATS_UPDATED`**: after a NATS update.
- **`UPDATED_REBOOT_SCHEDULED`**: after an update where `-Reboot` booked the restart. See `RebootScheduledAt`.
- **`RECOVERED_*`**: after a successful `-Recover`.
- **`RECOVERY_NOT_NEEDED`**: after a `-Recover` with nothing to recover.

### More on exit 5 and exit 10

Exit `5` is also returned when `-Reboot` booked a restart and a NATS update is still due.

Examples of a safe transient condition (exit `10`):

- **Veeam work** did not finish in time.
- **`CONCURRENT_RUN`**: another run is in progress.
- **`INSTALLER_NOT_PUBLISHED`**: EnterpriseDB has not yet published the Windows installer for a new minor. An audit can return this too.

### Failure codes win

Failure codes `20`–`50` take precedence over informational EOL/reboot codes. For example, an EOL server with a post-update service failure returns `40`, not `8`.

## Alert on NatsStatus too

When NATS is left alone, the exit code does not show it: it follows PostgreSQL. A run can return `0` (or `5`, `7`, `9`) while NATS was left alone for a reason worth a look.

Alert on these `NatsStatus` values. With any of the first five, a NATS update that may be due is not applied, run after run:

- **`HASH_CONFLICT`**, above all. It always adds to `ActionRequired`. It sets `IssueCode=NATS_HASH_CONFLICT` when no other issue is set.
- `REMOTE_CLIENTS`, `UNRECOGNISED_LAYOUT`, `HASH_UNAVAILABLE` and `POLICY_UNKNOWN_VB365`.
- **`NOT_RUNNING`** is worth a look too. It means `nats-server` is stopped or disabled on a VB365 server.

## Report fields

### Field order

The console summary and `last-result.json` hold every report field, in this order:

1. `Computer`
2. `Timestamp`
3. `Mode`
4. `VeeamProducts`
5. `PgMajor`
6. `PgInstalled`
7. `PgTarget`
8. `PgEol`
9. `NatsInstalled`
10. `NatsTarget`
11. `NatsStatus`
12. `NatsDetail`
13. `StaleEmRecord`
14. `StaleVeeamOneRecord`
15. `WshStatus`
16. `Stage`
17. `Outcome`
18. `ExitCode`
19. `RebootRequired`
20. `RebootScheduledAt`
21. `IssueCode`
22. `ActionRequired`
23. `JobsLeftDisabled`
24. `UnhealthyServices`
25. `ServicesStarted`
26. `ConsolesClosed`
27. `Vb365SyncStuck`
28. `RecoveryRunDir`
29. `Detail`
30. `LogPath`

These report fields are the RMM-readable issue note for any action-bearing result. They name what is unhealthy, what remains disabled, and where recovery evidence lives.

### What some fields tell you

| Field | What it tells you |
|---|---|
| `StaleEmRecord` | `present`: a leftover Enterprise Manager registry key was found. `removed; backup <path>`: `-RemoveStaleEnterpriseManagerRecord` deleted it |
| `StaleVeeamOneRecord` | The same, for a leftover Veeam ONE key and `-RemoveStaleVeeamOneRecord` |
| `WshStatus` | What happened to Windows Script Host. See [Windows Script Host and Veeam hardening](windows-script-host.md) |
| `ServicesStarted` | Stopped automatic Veeam services that the run started to rescue a failed configuration backup |
| `ConsolesClosed` | The Veeam consoles that the run closed |
| `Vb365SyncStuck` | Any VB365 organisation whose data sync is stuck. VB365 needs attention there |
| `last-result.json` | Every report field, in the order above, the same as the console summary |
| `result.json` | The same result, written to the run folder when the run has one. `-Install` creates one; `-Recover` uses the interrupted run's |

## Stage: how far the run got

Every summary line carries a `Stage=` field telling you exactly how far it got:

| Stage | What it means |
|---|---|
| `UNTOUCHED` | No schedule, service, or PostgreSQL state was changed. Guaranteed. Two other changes are still possible: see the notes below |
| `JOBS_DISABLED` | Schedules have been disabled; the installer has not started |
| `SERVICES_STOPPED` | Services are stopped; the PostgreSQL installer has not started. NATS update runs: see below |
| `INSTALLING` | **Mid-change.** The installer may have started; automatic rollback is prohibited |
| `VERIFIED` | PostgreSQL is at the target version. On a NATS update run: NATS is at its target version, and PostgreSQL was not touched |
| `COMPLETE` | Maintenance/state restoration completed. Inspect the exit code: exit `40` can still mean the completed recovery marker could not be removed |

Notes on `UNTOUCHED`:

- **Consoles**: an `-Install` run may have closed an open Veeam console. See `ConsolesClosed`.
- **Registry keys**: `-RemoveStaleEnterpriseManagerRecord` or `-RemoveStaleVeeamOneRecord` may have removed a leftover registry key, in an audit too. See `StaleEmRecord` and `StaleVeeamOneRecord`.

Note on `SERVICES_STOPPED`: on a NATS update run, this stage also covers:

- switching NATS
- starting VB365 on it
- switching NATS back on failure

Read `NatsStatus`.

## Reading the final state

- **Codes `10`, `11`, `20`, and `30`** normally mean nothing was changed or a safe pre-installer rollback succeeded.
- **Final state record**: always use `Stage`, `JobsLeftDisabled`, and `ActionRequired`.

> [!WARNING]
> Codes `40` and `50` can deliberately leave schedules disabled.

[Back to the README](../README.md) · [All docs](README.md)
