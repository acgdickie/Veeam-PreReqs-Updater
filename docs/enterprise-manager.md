# Enterprise Manager and leftover records

Read this page when a server has, or once had, Enterprise Manager: it covers how the script handles it and how to clear leftover records.

**In short**

- **Dump set:** the script discovers the Enterprise Manager database from the registry and adds it to the dump set.
- **Excluded (exit 11):** Enterprise Manager without VBR on a VB365 server, a database the script cannot read, and a database on another server.
- **Leftover registry key:** never counts as an installation alone. `-RemoveStaleEnterpriseManagerRecord` deletes it only when the same run proved Enterprise Manager is absent, after a verified `.reg` backup.
- **Leftover connection record:** lives inside the VBR configuration database. The separate manual tool `Clear-StaleEnterpriseManagerRecord.ps1 -Clear` can clear it, through an unsupported Veeam API.
- **RMM:** do not add that tool to the RMM. The RMM needs only `Update-VeeamPreReqs.ps1`.

## How Enterprise Manager is handled

Enterprise Manager has its own configuration database, separate from VBR's. The script discovers it from the registry and adds it to the dump set.

- **Registry layout:** the layout Veeam publishes in [KB1471](https://www.veeam.com/kb1471). It is the same layout as VBR, under `HKLM\SOFTWARE\Veeam\Veeam Backup Reporting`.
- **Default database name:** `VeeamBackupReporting`.
- **Services:** Enterprise Manager's own services (`VeeamEnterpriseManagerSvc`, `VeeamRESTSvc`) are already covered, because every `Veeam*` service is stopped and restored.

### Enterprise Manager on MS SQL

If Enterprise Manager is on MS SQL, it is simply not a PostgreSQL target. Its services are still stopped and restarted with the rest.

### PostgreSQL 16.x

Enterprise Manager 13 lists PostgreSQL 14.x, 15.x and 17.x; **16.x is absent**. The update never changes the major version. So a 16.x instance is only warned about, not blocked.

## Excluded topologies

Three topologies are still excluded:

- **Enterprise Manager without VBR** (`ENTERPRISE_MANAGER_WITHOUT_VBR`, exit 11), on a VB365 server. That needs its own profile for services and tuning.
- **A database the script cannot read** (`ENTERPRISE_MANAGER_DB_UNKNOWN`, exit 11). This means a pre-v12 registry layout, a missing value, an invalid port, or an unexpected engine name. Nothing is guessed.
- **An Enterprise Manager database on another server** (`REMOTE_DB`, exit 11), like any remote Veeam database.

A server with Enterprise Manager and neither VBR nor VB365 is not a target at all:

- **Exit:** `0`.
- **Outcome:** `Outcome=NOT_APPLICABLE`.
- **PostgreSQL:** not checked.

For all exit codes of the main script, see [Exit codes](exit-codes.md).

## Leftover records after an uninstall

An uninstall can leave records behind. Then the server would be excluded for a product that is not there. There are two separate records:

| Record | Where | How to clear it |
|---|---|---|
| Install footprint | Registry `HKLM\SOFTWARE\Veeam\Veeam Backup Reporting` | `Update-VeeamPreReqs.ps1 -RemoveStaleEnterpriseManagerRecord` |
| Connection record | Inside the VBR configuration database | `Clear-StaleEnterpriseManagerRecord.ps1 -Clear` |

### Install footprint: the registry key

The registry key alone never counts as an installation. The script also needs an Enterprise Manager **service** or its **installed files**. With only the key, the run continues and logs that it found a leftover record.

`-RemoveStaleEnterpriseManagerRecord` deletes that key only when the same run proved Enterprise Manager is absent.

- **Backup first:** it exports a `.reg` backup and verifies it. No backup means no deletion.
- **Backup file:** `stale-enterprise-manager-record-<timestamp>.reg` in the log folder.
- **Scope:** it never touches the Veeam configuration database.
- **Failure:** if the backup or the removal fails, the run stops with exit `20` and `IssueCode=STALE_EM_RECORD_REMOVE_FAILED`.

The report field `StaleEmRecord` shows the result:

| `StaleEmRecord` | Meaning |
|---|---|
| `present` | A leftover key was found |
| `removed; backup <path>` | The key was deleted |

### Connection record: inside the VBR database

`Clear-StaleEnterpriseManagerRecord.ps1` covers the record inside the VBR database. See [the separate tool](#the-separate-tool-clear-staleenterprisemanagerrecordps1) below.

> [!WARNING]
> Clearing the record uses an **unsupported API**. `[Veeam.Backup.Core.SBackupOptions]` is an internal Veeam class with no public documentation. It writes directly to the VBR configuration database.
>
> Veeam Support does not support this, and the class can change between versions. The supported route is to remove this VBR server from the Enterprise Manager console, or to ask Veeam Support.
>
> Test on a non-production VBR first.

## The separate tool: `Clear-StaleEnterpriseManagerRecord.ps1`

### What it is

A small manual tool for one leftover: the Enterprise Manager connection record inside the VBR configuration database. It changes nothing unless you pass `-Clear`.

It shows what the record holds:

- **Server:** the name and URL of the Enterprise Manager server.
- **Connection state:** whether VBR is connected to it.
- **Licence updates:** the licence-update settings.

### Why it is there

When a VBR server is added to Enterprise Manager, VBR stores this record. The supported way to remove it is to remove the VBR server from the Enterprise Manager console.

Once Enterprise Manager is uninstalled, that console is gone. So the record can stay behind, and the supported route left is to ask Veeam Support.

This tool can check for the record. It can also clear it without Support, through the unsupported class described above. It is for servers where Enterprise Manager has been uninstalled.

### Why it is not part of `Update-VeeamPreReqs.ps1`

- **Never read.** The PostgreSQL update does not need it. `Update-VeeamPreReqs.ps1` never reads this record.
- **Writes stay manual.** `-Clear` writes to the VBR configuration database through the unsupported class above. Inside the main script, that write would be one switch away on every server the RMM reaches. As a separate script, a person runs it by hand, on one server, after reading its report.
- **Reads can fail.** Reading the record uses the same internal class, which may not exist on every VBR version. Kept apart, that can never stop a PostgreSQL update.

Of the two records, `Update-VeeamPreReqs.ps1` uses only the registry key:

- **Backup decision:** together with the Enterprise Manager services and install folders, it decides whether an Enterprise Manager database must also be backed up.
- **Leftover removal:** with `-RemoveStaleEnterpriseManagerRecord`, it deletes the key when it is a leftover.

> [!IMPORTANT]
> Do not add `Clear-StaleEnterpriseManagerRecord.ps1` to the RMM. For the update, the RMM needs only `Update-VeeamPreReqs.ps1`.

### How to run it

Run it on the VBR server, from an elevated prompt.

- **VBR 12** works in Windows PowerShell 5.1.
- **VBR 13** needs PowerShell 7 (7.6.3 or later for VBR 13.1).

```powershell
.\Clear-StaleEnterpriseManagerRecord.ps1          # report only, changes nothing
.\Clear-StaleEnterpriseManagerRecord.ps1 -Clear   # checks, backs up, asks you, then clears
```

### Exit codes of the tool

| Exit | Meaning |
|---|---|
| `0` | No record, the record is already empty, or `-Clear` cleared it and read it back empty |
| `5` | A record exists. Report only, so nothing was changed |
| `1` | Nothing was changed, or the record may have changed. See the two cases below |

Exit `1` covers two cases:

- **Nothing was changed:** the tool could not run or read the record, `-Clear` refused, or you did not confirm (or used `-WhatIf`).
- **The record may have changed:** the write failed, the record could not be read back after the write, or it read back not empty.

If the record may have changed, check the VBR console. Restore the configuration backup if VBR misbehaves.

### What `-Clear` checks before it writes anything

1. **Enterprise Manager is not installed.**
   - **Services:** no Veeam service has "Enterprise Manager" in its name.
   - **Folder:** no folder exists at the default install path `C:\Program Files\Veeam\Backup and Replication\Enterprise Manager`.
   - **Custom path:** a custom install path is not checked.
2. **A fresh VBR configuration backup succeeds.** The tool takes this backup itself.
   - `Success` and `Warning` both pass, because both write a backup file.
   - A failure stops the tool, and it prints the reason from the backup's session log.
   - With `-WhatIf` no backup is taken.
   - `-SkipConfigBackupCheck` skips this step, for a lab server only.
3. **You confirm the change** at the prompt.

After the write it reads the record back, and fails if the record is not empty.

### Why it takes a fresh backup

The tool takes a fresh backup instead of trusting an older one. `LastRun` can be empty on VBR 12 and 13 builds, so the age of an older backup cannot be proven.

[Back to the README](../README.md) · [All docs](README.md)
