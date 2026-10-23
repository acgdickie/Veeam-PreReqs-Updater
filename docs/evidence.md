# Logs, backups and evidence

Read this page when you need a run's logs, results or recovery backups, want to know how their folder is protected, or must plan disk space.

**In short**

* **Default WorkRoot**: everything lives under `C:\ProgramData\VeeamPgUpdate`.
* **Results**: each run overwrites `logs\last-result.json`, and each `-Install` run also keeps its own `runs\<timestamp>\result.json`.
* **Locked**: the WorkRoot and newly created evidence tree are locked to SYSTEM and Administrators. An unsafe WorkRoot returns `WORKROOT_UNSAFE` (exit 20), and the script writes no file there.
* **Housekeeping** runs every time. It keeps unresolved runs and the two newest completed recovery sets, regardless of age.
* **Disk space**: the evidence files are local recovery assets, not merely script logs. Size the work volume for logical dumps plus a full cold copy.

## Folder layout

```
C:\ProgramData\VeeamPgUpdate\
  CHANGES-IN-PROGRESS.marker   present only mid-change, or after a run that needs a human
  .veeam-pg-updater            marks the folder as created by the script
  logs\
    VeeamPgUpdate_<server>_<timestamp>.log   full transcript
    last-result.json                          machine-readable result
    stale-enterprise-manager-record-<timestamp>.reg   backup of a leftover key that
                                              -RemoveStaleEnterpriseManagerRecord deleted
    stale-veeam-one-record-<timestamp>.reg    backup of a leftover key that
                                              -RemoveStaleVeeamOneRecord deleted
  runs\<timestamp>\
    recovery-state.json       versioned state used by -Recover
    result.json               this run's result (logs\last-result.json is overwritten by each run)
    backup\
      <database>.dump        pg_dump custom format
      globals.sql            roles and grants
      conf\                  the four .conf files from before the update
      datadir\               cold copy of the whole data directory
      datadir-acl.txt         original data-directory DACLs for a manual restore
      Config.xml             VB365 only
      Proxy.xml              VB365 only; controller and persistent-cache connections
    disabled-jobs.json
    veeam-service-state.json
    pg-service-state.json
    nats-service-state.json       when nats-server is installed
    pg-tuning.sql
    postgresql-<version>-windows-x64.exe   the downloaded installer, removed on success
    pg_installer_debug.log    the installer's debug trace
    installer-*.log
  runs\<timestamp>\               a NATS update run holds the same recovery-state.json,
                                  result.json, disabled-jobs.json and *-service-state.json,
                                  but no dumps, cold copy, tuning or installer files. Also:
    nats\                          the downloaded zip and the checked program, removed on success
    backup\
      Config.xml, Proxy.xml
      nats\
        nats-server-service.reg     the service's registry key
        nats-server.conf            the config file (it holds the NATS credentials)
        store\                      copy of the whole message store
        store-acl.txt               the store folder's original permissions
```

## How the WorkRoot is protected

### Locked permissions

* **Lock**: the WorkRoot and newly created evidence tree are locked to SYSTEM and Administrators.
* **Source DACLs**: the cold copy records the source DACLs separately. It does not import them into the evidence tree.

> [!WARNING]
> The dumps are privileged. Restoring one runs code chosen by whoever made it.

### Checks before any file is written

Before it writes even an audit log, the script verifies:

* the WorkRoot owner and ACL
* the WorkRoot's parent
* the `.veeam-pg-updater` sentinel
* that no active path component or top-level child is a junction/symbolic link

### Other checks

* **Recovery paths** are checked again before use.
* **Run folders**: a run is recursively checked for reparse points before retention can delete it.
* **Marker filename**: a marker filename by itself is not trusted.

### When a check fails

A failure returns `WORKROOT_UNSAFE` (exit 20). The script writes no file in the rejected location. See [Exit codes](exit-codes.md).

## WorkRoot location

### Why C:\ProgramData

* **Default**: the WorkRoot is `C:\ProgramData\VeeamPgUpdate`.
* **Always there**: `C:\ProgramData` exists on every Windows server.
* **Protected**: ordinary users cannot delete or replace what is in it.

So the script can create its folder there safely.

### Do not use C:\temp

Do not use a folder under a typical `C:\temp`. Every signed-in user can normally change it. So the script refuses it (`WORKROOT_UNSAFE`).

### Rules for a custom WorkRoot

* **Parent**: the parent of a custom WorkRoot must already exist.
* **Ancestors**: every ancestor must be non-reparse and non-replaceable.

### Existing WorkRoots and rejected paths

* **Existing non-empty WorkRoot**: used only when it has the exact protected ACL and trusted sentinel created by this script.
* **Existing empty WorkRoot**: must already have that exact protected ACL before the script will claim it.

The script rejects these without changing their contents or permissions:

* drive roots
* UNC paths
* relative paths
* foreign content
* forged sentinels
* reparse points

### A folder the script cannot prove it created

The script refuses a `C:\ProgramData\VeeamPgUpdate` folder that it cannot prove it created (`WORKROOT_UNSAFE`). For example, it refuses one left by an early version.

If that folder holds no `CHANGES-IN-PROGRESS.marker`, rename it and run again.

## The former C:\temp work root

Earlier versions used `C:\temp\VeeamPgUpdate` as the work root. The script also checks it for a trusted changes-in-progress marker.

If it finds one, it returns `LEGACY_WORKROOT_RECOVERY_REQUIRED` (exit 40). It does this rather than hiding an interrupted run.

To clear it:

1. Follow the RMM instruction to run `-Recover -WorkRoot C:\temp\VeeamPgUpdate`.
2. After recovery, normal runs can use the default.

That `-Recover` run makes the same WorkRoot checks as any other run, on `C:\temp` too. So on a typical `C:\temp` it is refused (`WORKROOT_UNSAFE`, exit `20`).

`-Recover` on `C:\temp` runs only when both are true:

* `C:\temp` is owned by SYSTEM or an administrator.
* `C:\temp` gives ordinary users no right to delete, re-permission or take over what is in it.

## Housekeeping

**Housekeeping runs every time**, audits included.

* **Transcript logs** older than [`retentionDays`](settings.md) (default 30) are eligible for deletion.
* **Completed recovery sets** older than `retentionDays` are eligible for deletion.
* **Two newest completed sets** are retained regardless of age.
* **Unresolved runs** are retained regardless of age.
* **Recovery marker**: if a recovery marker exists, no run folder is purged.
* **Audit runs** do not create a recovery-set folder. `-Install` does.

## Disk space and off-host copies

The evidence files on this page are local recovery assets, not merely script logs.

* **Size** the work volume for logical dumps plus a full cold copy.
* **Copy** them off-host if required by your backup policy.

[Back to the README](../README.md) · [All docs](README.md)
