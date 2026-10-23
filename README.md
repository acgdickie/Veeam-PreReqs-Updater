# Veeam PreReqs Updater

**Keeps the PostgreSQL under your Veeam servers patched. Safely, from your RMM.**

`Update-VeeamPreReqs.ps1` updates two prerequisites that Veeam installs on Windows:

- **PostgreSQL**, the database under Veeam Backup & Replication (VBR) and Veeam Backup for
  Microsoft 365 (VB365, also called VBM).
- **NATS**, the message server VB365 8 uses for its job queue.

It is built to run unattended from an RMM (remote monitoring and management) tool, across
many servers.

[Try it](#try-it) · [Will it work on my server?](#will-it-work-on-my-server) ·
[Before you run -Install](#before-you-run--install) · [Exit codes](#exit-codes) ·
[If it goes wrong](#if-it-goes-wrong) · [All docs](docs/README.md)

## Why it matters

- **Veeam does not update them.** Upgrading Veeam on Windows leaves PostgreSQL on its old
  version ([KB4729](https://www.veeam.com/kb4729)). NATS on VB365 stays old too
  ([KB4742](https://www.veeam.com/kb4742)).
- **So the server misses fixes.** Later PostgreSQL minor releases carry security and bug
  fixes that the old one does not have.
- **By hand, it is slow.** Veeam's steps ([KB4386](https://www.veeam.com/kb4386) for VBR,
  [KB4729](https://www.veeam.com/kb4729) for VB365) take time and care on every server. This
  script does them the same safe way everywhere.

> [!WARNING]
> This is outside Veeam Support's scope: Veeam's KBs for these steps cite Support Policy
> section 10. Run an audit first, and pilot on one non-production server. If it breaks, the
> backups this script takes are your only safety net.
>
> Tested so far on 2 × VBR 12, 2 × VBR 13 and 1 × VB365 8.6 servers, in production after
> testing. All issues found so far are fixed, but other bugs may still exist.

## Try it

1. Copy `Update-VeeamPreReqs.ps1` to the server. It is the only file you need.
2. Open PowerShell as administrator, in that folder.
3. Run an audit. It checks the server and reports what is due. It changes nothing.

```powershell
# VBR 12: Windows PowerShell 5.1
powershell -ExecutionPolicy Bypass -File .\Update-VeeamPreReqs.ps1

# VBR 13 and VB365: PowerShell 7
pwsh -ExecutionPolicy Bypass -File .\Update-VeeamPreReqs.ps1
```

The `RMM ACTION` line at the end says what to do next. Exit `5` means an update is waiting.
Read [Before you run -Install](#before-you-run--install) before you apply it.

## What it does

| Switch | What it does |
|---|---|
| none (audit) | Checks the server and reports what is due. Changes nothing. |
| `-Install` | Applies the update. |
| `-Reboot` | With `-Install`: schedules a Windows restart after a fully successful PostgreSQL update (120 seconds later, by default). |
| `-Recover` | Finishes an interrupted run, or undoes it if the installer had not started. If it cannot prove the run is safe to finish, it only reports. |
| `-WorkRoot` | Folder for logs, backups and the run marker. Default: `C:\ProgramData\VeeamPgUpdate`. Use the same one for every run on a server. |

More switches, and the built-in settings: [Parameters and settings](docs/settings.md).

### What gets updated

- **PostgreSQL:** to the newest minor release on the same major version. For example, 15.2
  goes to the latest 15.x. Never to 16 or 17, and never to an older version.
- **NATS (VB365 only):** to the newest version Veeam lists on the same 2.x line.
- **One change per run:** PostgreSQL first. NATS on the next `-Install` run.

### What an `-Install` run does

It waits for Veeam work to finish, turns off the scheduled jobs and backs up. Then it stops
Veeam, installs the update and checks it. Last, it starts Veeam and turns back on the jobs it
turned off. Every step is in [How it works](docs/how-it-works.md).

### Safe by design

- **Never force-stops a backup or restore.** It waits for Veeam work to finish.
- **Updates only.** No major-version upgrade. No downgrade.
- **Checks the download.** EnterpriseDB's signature on the PostgreSQL installer, and the
  published SHA256 for NATS.
- **Backs up first.** A VBR configuration backup (on VB365, `Config.xml` and `Proxy.xml`), a
  dump of every Veeam database, and a full copy of the PostgreSQL data folder.
- **Undoes a failure before the installer starts.** If that undo fails, the run returns `40`.
- **Stops for a person after that.** Nothing is rolled back once the installer starts. Veeam
  can stay stopped and jobs off (exit `40` or `50`). Restoring from the backups is a manual job.
- **Handles Windows Script Host hardening.** It turns Windows Script Host on only while the
  PostgreSQL installer runs.

## Will it work on my server?

| Server | Result |
|---|---|
| VBR on Windows, with one local PostgreSQL used only by Veeam. Enterprise Manager beside VBR is fine. | ✅ Supported |
| VB365 8.6 or later on Windows, with one local PostgreSQL used only by Veeam | ✅ Supported |
| No Veeam product uses a local PostgreSQL (for example, VBR on Microsoft SQL Server) | ➖ Nothing to do (exit `0`) |
| Enterprise Manager with neither VBR nor VB365 | ➖ Nothing to do (exit `0`) |
| Veeam ONE installed, with or without VBR or VB365 | ❌ Exit `11` |
| VBR and VB365 on the same server | ❌ Exit `11` |
| VB365 8.0 to 8.5 | ❌ Exit `11` |
| Enterprise Manager on a VB365 server without VBR, or with a database the script cannot read | ❌ Exit `11` |
| A remote database, remote VB365 proxies, more than one PostgreSQL, or a clustered (HA) one | ❌ Exit `11` |
| Veeam Linux appliance | ❌ Refused. Veeam Updater patches it. |

Exit `11` means: handle that server by hand, and do not keep retrying it. A few rarer setups
also return `11`, for example a job type the script cannot safely turn off and on again. The
full rules are in [Scope and known limits](docs/scope-and-limits.md).

## Before you run `-Install`

> [!IMPORTANT]
> - Run it elevated, from your own RMM agent or a Windows scheduled task.
> - **Not** through the Veeam Management Agent. The script stops that agent during the update.
> - **Not** over WinRM or `Invoke-Command`. The PostgreSQL installer is known to fail there.
> - Use the right PowerShell: `pwsh` (PowerShell 7) on VBR 13 and VB365, and Windows
>   PowerShell 5.1 (`powershell`) on VBR 12. In the wrong one, an audit or `-Install` stops
>   before it changes anything (exit `20`).
> - Set your RMM's script timeout well above the longest run (see below). A run killed
>   part-way can leave jobs off, Veeam stopped and Windows Script Host on, until you run
>   `-Recover`.

### What to expect

- It can take hours. Each wait for Veeam work can last up to 12 hours by default, and one run
  can wait more than once. The installer gets up to 2 hours more.
- It all happens in one run. The outage starts when Veeam goes quiet, which can be hours after
  the run starts.
- **It closes open Veeam consoles** (VBR and VB365) once they are the only thing in the way.
  Unsaved work in them is lost. It never closes a Veeam Explorer. It waits for the Explorer
  to close, then returns `10`, or `40` with jobs left off if it is still open after the update.
- A PostgreSQL update needs a restart:
  - Without `-Reboot`, the run returns `6` (`8` on an end-of-life branch). The jobs are back
    on by then, so restart when no Veeam job is running.
  - With `-Reboot`, the script schedules the restart and returns `0` (`7` on an end-of-life
    branch), unless a last check finds Veeam work running. A job that starts inside the
    delay is cut off by the restart.
  - A NATS update needs no restart.

### What it needs

- Internet access to postgresql.org and EnterpriseDB. VB365 servers also need
  helpcenter.veeam.com, and GitHub when a NATS update is due. Behind a proxy that inspects
  TLS, test this first.
- Free disk space on the WorkRoot drive: 400 MB, plus twice the size of the PostgreSQL data
  folder, plus 1 GB.
- Nothing that blocks `wscript.exe` or `cscript.exe`, such as AppLocker, WDAC or Software
  Restriction Policies. The script cannot detect these, and they make the PostgreSQL
  installer fail.
- A plan for the backups. They stay on the server for at least 30 days. Copy them off the
  server if your policy needs that.

## Roll out to a fleet

1. Audit every server. Note the `5`, `7`, `9` and `11` results. Look into any `20`, `40` or
   `50` before you go further.
2. Pilot each new PostgreSQL minor, Veeam version and PowerShell edition on one
   non-production VBR server and one non-production VB365 server.
3. Roll out in rings: a small production ring and a soak period first, then the rest.
4. Act on the [exit codes](#exit-codes).

Your rings are the approval step. The script has no version allow-list: it always picks the
newest minor on the installed major version. Read each new minor's release notes, because a
rare one needs follow-up work, such as `REINDEX`.

Freeze manual work during `-Install`. The script turns off every schedule, but it cannot stop
someone starting a job by hand from another machine.

More in [Running it from an RMM, and rebooting](docs/running-from-an-rmm.md).

## Exit codes

Every run ends with a summary for your RMM, which holds the fields named below. This one is
from an audit, shortened (`...`):

```text
=== RMM SUMMARY ===
Computer=VEEAM-SRV01; Timestamp=2026-10-22T09:30:15; Mode=AUDIT; VeeamProducts=VBR; PgMajor=15; PgInstalled=15.12; PgTarget=15.19; ... Stage=UNTOUCHED; Outcome=UPDATE_AVAILABLE; ExitCode=5; ...
RMM ACTION: Schedule an -Install run for the update named in Detail (the latest same-major PostgreSQL minor, or a same-line NATS update on VB365).
RMM ISSUE: UPDATE_AVAILABLE | Update available: PostgreSQL 15.12 -> 15.19 for VBR. Re-run with -Install to apply. Nothing was changed.
===================
```

Point your RMM alerts at these exact values:

| Code | What it means | What to do |
|---|---|---|
| `0` | Healthy, or finished. | Nothing. After `-Recover` finished an update, restart. After any restart, run an audit. |
| `5` | An update is available. | Schedule `-Install`. |
| `6` | Updated. A restart is needed. | Restart, then run an audit. |
| `7` | The PostgreSQL branch is end-of-life (EOL). | Open a major-version migration ticket. |
| `8` | EOL, and a restart is needed. | Restart. Keep the migration ticket. |
| `9` | EOL, and an update is available. | Schedule `-Install`. Keep the migration ticket. |
| `10` | Not now. For example, Veeam work did not finish in time, another run was going, or the installer is not out yet. | Let the RMM retry later. Read `Detail` if it keeps happening. |
| `11` | This setup is not supported. | Handle it by hand. Do not keep retrying. |
| `20` | A check failed. Nothing was changed, or this run put its changes back (a failed NATS update included). | Investigate before you retry. |
| `30` | A download or its check failed. Nothing was installed. | Read `Detail`. A failed signature or SHA256 is not a network fault. |
| `40` | **Needs a person.** Something failed after a change, or recovery needs a decision. | Page someone. Read `ActionRequired`. |
| `50` | **Needs a person now.** After the update, tuning or a `-Recover` check, PostgreSQL is missing, down, unqueryable or on the wrong version. | Page someone now. |

- When NATS is left alone, the exit code does not show it: the code follows PostgreSQL. Alert
  on `NatsStatus` too, above all `NatsStatus=HASH_CONFLICT`. That means the NATS release no
  longer matches the SHA256 built into the script.
- A run that passes the WorkRoot check also saves its result to `logs\last-result.json` in
  the WorkRoot. Alert on the exit code, not on this file.

What every code and field means: [Exit codes and report fields](docs/exit-codes.md).

## If it goes wrong

1. Read the result. Start with `ExitCode`, `Stage`, `IssueCode` and `ActionRequired`.
2. Do what `ActionRequired` says. `JobsLeftDisabled` lists any jobs still turned off.
3. Was the run interrupted? Run `-Recover`, in the right PowerShell. Before the installer
   started, it puts things back. After that, it finishes the run only if PostgreSQL is
   healthy at the target version. Otherwise it only reports (exit `40` or `50`).
4. Leave `CHANGES-IN-PROGRESS.marker` alone. It sits in the WorkRoot and makes every later
   audit and `-Install` return `40` until the run is closed. Do not delete it to make the
   next run go.

The full guide is [If it goes wrong](docs/troubleshooting.md). It also covers
[Closing out an earlier run by hand](docs/troubleshooting.md#closing-out-an-earlier-run-by-hand).

## Documentation

| Page | Read it when |
|---|---|
| [How it works](docs/how-it-works.md) | You want every step, and why it is there |
| [Exit codes and report fields](docs/exit-codes.md) | You set up RMM alerts, or read a result |
| [Parameters and settings](docs/settings.md) | You need a switch or setting not shown above |
| [Running it from an RMM, and rebooting](docs/running-from-an-rmm.md) | You plan a rollout, or use `-Reboot` |
| [NATS updates (VB365)](docs/nats.md) | You look after VB365 servers |
| [Windows Script Host and Veeam hardening](docs/windows-script-host.md) | Your servers follow Veeam's hardening advice |
| [Logs, backups and evidence](docs/evidence.md) | You need a log or a backup, or want to know what is kept |
| [If it goes wrong](docs/troubleshooting.md) | A run returned `40` or `50`, or was interrupted |
| [Enterprise Manager and leftover records](docs/enterprise-manager.md) | Enterprise Manager is, or was, installed |
| [Scope and known limits](docs/scope-and-limits.md) | A server returned `11`, or you want the full rules |
| [Testing](docs/testing.md) | You change the script |

## Report a problem

Please raise an issue or a pull request. In an issue, include as much as you can, so the
problem can be reproduced:

- when you downloaded the script, or its commit ID
- the Veeam product and version, and the PowerShell edition
- `ExitCode`, `Stage` and `IssueCode`
- the log from the run, with server and customer names removed

## Files

| File | What it is |
|---|---|
| `Update-VeeamPreReqs.ps1` | The update script. The only file your RMM needs. The settings are built in. |
| `Clear-StaleEnterpriseManagerRecord.ps1` | A separate tool you run by hand. Not for the RMM. See [Enterprise Manager](docs/enterprise-manager.md). |
| `Test-Helpers.ps1` | Tests, for people who change the script. Never copy it to a Veeam server. See [Testing](docs/testing.md). |

## Changelog and licence

- What changed, and when: [CHANGELOG.md](CHANGELOG.md)
- Licence: [MIT](LICENSE)
