# NATS updates (VB365)

This page explains how the script checks and updates NATS on VB365 servers, and what each `NatsStatus` value means. Read it before the first NATS update, or when a report shows a `NatsStatus` you need to understand.

**In short**

* **NATS** is the message server VB365 8 uses for its job queue. A VB365 upgrade never updates it, so the script does, following Veeam [KB4742](https://www.veeam.com/kb4742).
* **Same 2.x line only.** The script updates to the newest version Veeam lists on the installed line. It never moves to another line and never downgrades.
* **One change per run.** When PostgreSQL also needs an update, `-Install` updates PostgreSQL. The next `-Install` run updates NATS.
* **Anything the script cannot prove** leaves NATS alone, with the reason in `NatsDetail`. Leaving NATS alone never blocks a PostgreSQL update.
* **Rollback is automatic.** If the switch or the start-and-verify step (step 5 or 6) fails, the old NATS goes back and the run returns exit `20`.

## What NATS is

NATS is the message server VB365 8 uses for its job queue. It runs as the `nats-server` Windows service.

A VB365 upgrade never updates NATS. Veeam leaves that to you and documents the steps in [KB4742](https://www.veeam.com/kb4742). The script follows those steps, with backups, checks and an automatic rollback added.

VBR does not use NATS, so on VBR `NatsStatus=NOT_APPLICABLE`.

## Before the first update

> [!IMPORTANT]
> Before the first NATS update, run the audit on the VB365 servers and read `NatsStatus` and `NatsDetail`.

The NATS update has been tested on a live VB365 server: NATS 2.10.22 went to 2.10.28, and VB365 worked on the new version. Other servers can be set up differently, so audit first. An `UNRECOGNISED_LAYOUT` result names the part that differs.

## Version policy

### An update, never an upgrade

Veeam supports an exact list of NATS versions per VB365 release, not a range ([system requirements](https://helpcenter.veeam.com/docs/vbo365/guide/vbo_system_requirements.html)).

* **Same line only.** The script moves NATS only to the newest version on that list that is on the same 2.x line as the installed one.
* **No line changes.** A move to another line changes the message-store format and has no documented way back. The script never does it.

### Where the list comes from

The script reads the list from Veeam's website on every run. So a version Veeam adds is picked up without a script change.

The script uses the page only when it describes the server's own VB365 release. The page says "Page content applies to build 8.6.0.1102", and that must be 8.6 on an 8.6 server.

In these cases an 8.6 server falls back to the 8.6 list built into the script, and nothing from the page is used:

* **Page shows a newer release.** Veeam's page always shows the newest VB365 release. So after Veeam ships 8.7, an 8.6 server falls back to its built-in 8.6 list.
* **Page cannot be read.**
* **List sentence changed.** The page's NATS sentence no longer reads as one plain list: "NATS server" followed by versions separated by commas, "and" or "or", ending in a full stop.

`NatsDetail` names the list used.

### Releases other than 8.6

Only 8.6 has a list built in. A server on another release gets NATS updates only while Veeam's page describes that release and can be read.

Otherwise it reports `POLICY_UNKNOWN_VB365` until its list is added to `SupportedByVb365` in `Get-NatsPolicy`.

### VB365 8.6 versions

For VB365 8.6 the list is 2.10.18, 2.10.22, 2.10.28, 2.12.5 and 2.12.8 (October 2026):

| Installed | Result |
|---|---|
| 2.10.x below 2.10.28 (for example 2.10.18, 2.10.22 or 2.10.25) | Update to 2.10.28 |
| 2.12.x below 2.12.8 (for example 2.12.5, 2.12.6 or 2.12.7) | Update to 2.12.8 |
| 2.10.28 or 2.12.8 | `CURRENT`, nothing to do |
| 2.10.29, 2.12.9 or later on a line | `AHEAD`, left alone. Never downgraded |
| 2.11.x, 2.14.x, any other line | `UNLISTED`, left alone |

### One change per run

When PostgreSQL also needs an update, `-Install` updates PostgreSQL and reports `NatsStatus=UPDATE_PENDING`. The next `-Install` run updates NATS.

Each change then has its own outage and its own rollback. You always know which one caused a problem.

## Download check (SHA256)

NATS publishes no signature, so the download is checked against a SHA256.

* **`SHA256SUMS` file.** Each [NATS release](https://github.com/nats-io/nats-server/releases) has a `SHA256SUMS` file. The download must match the line for its `windows-amd64.zip`.
* **No match.** A download that does not match is deleted. The run returns exit `30` with nothing changed.

### The trust trade-off

The `SHA256SUMS` file comes from the same GitHub release as the download. It proves the file arrived whole.

It does not prove that the release itself is genuine. GitHub lets a release be changed after it is published.

* **Built-in SHA256.** For the versions known when the script was written (2.10.28 and 2.12.8), the script also has the SHA256 built in, in `Get-NatsPolicy`.
* **Conflict.** If the release's `SHA256SUMS` ever disagrees with it, the script installs nothing (`HASH_CONFLICT`).
* **Later versions.** A version Veeam adds later is checked against `SHA256SUMS` only. That is the trade-off for not editing the script.

## Checks before an update

The audit reads all of the items below and changes nothing. An update is only planned when every check passes:

* **Service.** The `nats-server` service runs `nats-server.exe` from a folder directly under `C:\Program Files\NATS`, with exactly `-c <config file>`.
* **Version.** `nats-server --version`, the folder name (when it carries a version), and the version NATS reports to a client on its port all agree.
* **Config file.** The config file names exactly one `store_dir`, and uses no `include`, `cluster`, `gateway` or `leafnodes`.
* **Store.** The store is a local folder outside `WorkRoot`.
* **VB365 connection.** `Config.xml` and `Proxy.xml` send VB365 to NATS on this server, on the port in the config file.
* **No other clients.** No other machine is connected to NATS.

Anything the script cannot prove leaves NATS alone, with the reason in `NatsDetail`. Leaving NATS alone never blocks a PostgreSQL update.

## What `-Install` does

When every check passes, `-Install` then:

1. **Downloads and tests.**
   * Downloads `nats-server-v<version>-windows-amd64.zip` from GitHub and checks its SHA256.
   * Extracts only `nats-server.exe`, and runs it with `--version` and `-t` (config check only).
   * Checks that the WorkRoot drive has room for a copy of the message store plus 200 MB (`LOW_DISK`, exit `20`).
   * Nothing has changed yet.
2. **Quietens VB365.** Waits for VB365 work to finish, disables the jobs, and starts VB365 maintenance mode, as for a PostgreSQL update.
3. **Stops services.** Stops every `Veeam*` service (Proxy first), then NATS. PostgreSQL keeps running.
4. **Backs up.** Backs up the service's registry key, the config file, the store folder's permissions, and the whole message store. Checks that the copy holds the same number of files and bytes.
5. **Switches.** Copies the new `nats-server.exe` into a new version folder beside the old one. Points the service at it through the Windows service manager, as KB4742 does with `sc.exe`. The old folder stays.
6. **Starts and verifies.**
   * Starts NATS on its own and checks the version clients get.
   * Then starts VB365 and waits 90 seconds.
   * Checks every service, PostgreSQL and the VB365 PowerShell connection.
   * Checks that VB365 connects to NATS again, when it was connected to NATS before.
7. **Finishes.** Ends maintenance mode, waits for any new Veeam work to finish, and turns the jobs back on. Returns exit `0` (or `7` on an EOL PostgreSQL branch) with `Outcome=NATS_UPDATED`.

A NATS update needs no restart, so `-Reboot` books none (see [Rebooting](running-from-an-rmm.md#rebooting)).

### If step 7 fails

Then:

* **NATS** stays on the new version (`NatsStatus=UPDATED`).
* **Schedules** stay disabled.
* **Exit** is `40`.
* **`-Recover`** then finishes the run.

## Rollback

### If step 5 or 6 fails

Before VB365 is verified healthy on the new version, the old NATS goes back automatically. The run returns exit `20` (`NATS_UPDATE_FAILED`, `NatsStatus=UPDATE_FAILED_REVERTED`).

What goes back depends on whether VB365 used the new version:

* **Before VB365 used the new version,** the service points back at the old program. If the new version started, the message store copy is put back too.
* **After VB365 used it,** VB365 is stopped and the service points back at the old program. The store is kept: old messages put back could make VB365 do work twice. The old version on the same line reads the store as it is.

### If the rollback fails

If the rollback itself fails, the script starts nothing on a half-switched NATS:

* **Jobs** stay disabled.
* **Veeam services** are not started again.
* **Exit** is `40`.

`ActionRequired` names the old program, the registry backup and the store copy. Fix the problem, then run `-Recover`: it tries the rollback again.

## Recovering an interrupted NATS run

`-Recover` on an interrupted NATS run does one of these:

* **Puts the old NATS back.** This happens unless VB365 was already started on the new version and NATS answers at that version. The result is `RECOVERED_NATS_REVERTED` (`NatsStatus=UPDATE_FAILED_REVERTED`).
* **Keeps the new version.** When VB365 was already started on the new version and NATS answers at that version, it keeps the new version and finishes the run (`RECOVERED_NATS_UPDATED`).
* **Finishes a step 7 run.** It also finishes a run that stopped in step 7, after VB365 was verified on the new version.
* **Restores services and jobs only.** It does this when the run stopped before NATS was changed (`RECOVERED_PREINSTALL`, `NatsStatus=NOT_UPDATED`).

The results `RECOVERED_NATS_UPDATED`, `RECOVERED_NATS_REVERTED` and `RECOVERED_PREINSTALL` all return exit `0`.

Two more rules:

* **Services started by hand.** If someone started Veeam services by hand before VB365 ever used the new version, `-Recover` changes nothing. It asks an operator to stop them first.
* **Recovery state version 2.** NATS runs write recovery state version 2. An older copy of this script refuses to recover one instead of guessing.

For exit codes in general, see [Exit codes](exit-codes.md). For `-Recover` in general, see [If it goes wrong](troubleshooting.md).

## `NatsStatus` values

| `NatsStatus` | What it means |
|---|---|
| `NOT_APPLICABLE` | Not a VB365 server |
| `NOT_LOCAL` | No `nats-server` service on this server |
| `NOT_RUNNING` | `nats-server` is stopped or disabled; it is only updated while it runs normally |
| `CURRENT` | The newest version Veeam lists on its line |
| `UPDATE_AVAILABLE` | An update is due. Audit returns exit `5` (or `9`) |
| `UPDATE_PENDING` | Due, but this run updated PostgreSQL. The next `-Install` run updates NATS |
| `UPDATES_OFF` | Due, but `updateNats` is `false` (see [Settings](settings.md)) |
| `UPDATED` | This run updated NATS |
| `UPDATE_FAILED_REVERTED` | The update failed and the old version is back |
| `NOT_UPDATED` | The run stopped before NATS was changed |
| `UPDATE_FAILED` | The run stopped while NATS was half-switched. Read `ActionRequired` |
| `AHEAD` / `UNLISTED` | Not on Veeam's list, or nothing on its line to update to. Left alone |
| `HASH_UNAVAILABLE` | Due, but the release's `SHA256SUMS` could not be read, and no SHA256 is built in. Each run checks again. See below |
| `HASH_CONFLICT` | Due, but the release's `SHA256SUMS` disagrees with the SHA256 built into the script. See below |
| `POLICY_UNKNOWN_VB365` | No NATS list for this VB365 release. `NatsDetail` says which cause applies. See below |
| `REMOTE_CLIENTS` | Another machine is connected to NATS |
| `UNRECOGNISED_LAYOUT` | NATS is not set up the way the script expects. `NatsDetail` says what |
| (empty) | The run ended before the NATS check. A `-Recover` run fills it only when it recovers a NATS update |

### `HASH_UNAVAILABLE`

One example cause: a proxy blocks `github.com` or `release-assets.githubusercontent.com`.

### `HASH_CONFLICT`

> [!WARNING]
> `HASH_CONFLICT` means the release may have been changed. Investigate before anything else.

* **Exit code** does not change.
* **`ActionRequired`** always reports the hash conflict.
* **`IssueCode`** says `NATS_HASH_CONFLICT` only when the run has no other `IssueCode`. Any non-zero exit (for example `5` when PostgreSQL also has an update) already sets one.

### `POLICY_UNKNOWN_VB365`

One of these is true, and the script has no list built in for the release:

* **Release unknown.** The server's release could not be identified.
* **Page unreadable.** Veeam's page could not be read.
* **Other release.** Veeam's page describes another release.

`NatsDetail` says which.

[Back to the README](../README.md) · [All docs](README.md)
