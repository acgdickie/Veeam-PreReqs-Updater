# Scope and known limits

Read this page before you add the script to an RMM policy: it lists supported servers, refused servers and known limits.

**In short**

* **Supported**: VBR-only or VB365-only servers on Windows, with one local, standalone PostgreSQL instance dedicated to the detected Veeam configuration/cache databases.
* **Exit `11`**: combined VBR+VB365, Veeam ONE co-residence and the other setups listed below need manual handling. There is no configuration switch to bypass this.
* **Minor updates only**: PostgreSQL goes to the latest release on its installed major. No major upgrades. No downgrades.
* **Out of Veeam Support scope**: if it breaks, the backups this script takes are your only safety net.
* **Pilot first**: pilot each new product, version and PowerShell edition on one non-production server before fleet rollout.

## Scope

### Supported setups

The initial production topology supports two kinds of target:

* **VBR-only**: Enterprise Manager beside VBR is allowed.
* **VB365-only**: needs VB365 8.6 or later.

Either one must be backed directly by one local, standalone PostgreSQL instance. That instance must be dedicated to the detected Veeam configuration/cache databases.

### Setups that return exit 11

These setups return exit `11` for manual handling:

* **Combined** VBR+VB365 servers.
* **Veeam ONE** co-residence.
* **Enterprise Manager on VB365**: Enterprise Manager on a VB365 server without VBR.
* **Enterprise Manager database**: one the script cannot read.
* **Remote or distributed** databases and proxies.
* **Multiple or HA** PostgreSQL instances.

See [Known limits](#known-limits) for the detailed list.

### Not a target: exit 0

A server with Enterprise Manager and neither VBR nor VB365 is not a target. The script returns exit `0` (`NOT_APPLICABLE`). See [Leftover Enterprise Manager records](enterprise-manager.md).

### Veeam ONE leftover key

Veeam ONE counts as installed only when its `HKLM:\SOFTWARE\Veeam\Veeam ONE` key has a Veeam ONE service or installed-programs entry behind it.

* **Leftover key**: a key left by an uninstall is logged as a leftover. It does not block.
* **Removal**: `-RemoveStaleVeeamOneRecord` deletes such a leftover key, after a `.reg` backup. See [Settings](settings.md).

### Windows only

On the Veeam Linux appliance, PostgreSQL comes from Veeam Updater. Do not hand-patch those. The script refuses.

### Minor updates only

Updates always go to the latest release on the installed major.

* **Branch**: the script reads the running PostgreSQL branch and selects its latest published minor.
* **Example**: 15.2 becomes the latest 15.x release. It never becomes 16.x or 17.x.
* **No override**: there is no target override or version allow-list.

### Major upgrades blocked

Major upgrades are hard blocked. A branch change needs `pg_upgrade` or a Veeam configuration restore. That is outside this script.

### No downgrades

If the running version is equal to or newer than the resolved target, the script leaves PostgreSQL alone.

On VB365, an `-Install` run still updates NATS when a same-line NATS update is due. See [Updating NATS](nats.md).

### EOL branches stay on their branch

The script warns, then targets the final minor published for that branch. It returns a distinct EOL exit code until a major-version migration is completed. See [Exit codes](exit-codes.md).

### Out of Veeam Support scope

> [!WARNING]
> This script is out of Veeam Support scope. Both KBs it follows, [KB4386](https://www.veeam.com/kb4386) (VBR) and [KB4729](https://www.veeam.com/kb4729) (VB365), cite Support Policy section 10. If it breaks, the backups this script takes are your only safety net.

## Tested on

The servers it has been tested on are listed at the top of the [README](../README.md), in the warning box. To report a problem, see [Report a problem](../README.md#report-a-problem).

## Known limits

### Exit 11 in detail

Enterprise Manager beside VBR is supported. See [Leftover Enterprise Manager records](enterprise-manager.md).

The initial production profile intentionally returns exit `11` for:

* **Combined** VBR+VB365 servers.
* **Veeam ONE** co-residence.
* **Enterprise Manager on VB365**: Enterprise Manager on a VB365 server without VBR.
* **Enterprise Manager database**: one the script cannot read, or one that is on another server.
* **Remote databases**: remote VBR/VB365 databases, or distributed VB365 proxies.
* **Multiple PostgreSQL**: multiple PostgreSQL installations, different Veeam database ports, or HA/clustered PostgreSQL.
* **Pooler or proxy**: a PostgreSQL pooler/proxy in the connection path.
* **Non-Veeam databases**: unexpected non-Veeam databases in the cluster.
* **VB365 connections**: VB365 controller/cache connections that do not all map to the local instance.
* **Scheduler families**: any installed scheduler family that cannot be enumerated, disabled, re-enabled, and verified through the available Veeam PowerShell module.

### Storage-copy and Catalyst-copy

In particular, current VBR storage-copy and Catalyst-copy wrappers do not expose their original enabled/schedule state. If either object type exists, the script fails closed. It does not guess how to round-trip it.

### No bypass switch

There is no configuration switch to bypass those exit `11` exclusions. Add support only through a tested profile that protects every database, proxy, service, and schedule involved.

### No checksums from EnterpriseDB

EnterpriseDB publishes no checksums. The Authenticode signature is the only authenticity control. Behind a TLS-inspecting proxy, test it before fleet rollout.

### NATS has no signature

A NATS version Veeam adds later is checked only against the `SHA256SUMS` file in its own GitHub release. So a release changed after publication would not be caught.

Only 2.10.28 and 2.12.8 also have a SHA256 built into the script. See [Updating NATS](nats.md).

### More sites to reach on VB365

| When | Sites read |
|---|---|
| Every run, audit included | `helpcenter.veeam.com` |
| A NATS update is due | Also the release's `SHA256SUMS` from `github.com`, which redirects to `release-assets.githubusercontent.com` |
| `-Install` downloads NATS | The same two GitHub hosts |

### Single-server NATS only

No cluster, gateway, leaf node, or client on another machine.

### Application backup policies: internal Veeam API

The supported cmdlet does not expose whether a SAP HANA, Oracle RMAN or SAP on Oracle policy is enabled. So the script reads it from `[Veeam.Backup.Core.CBackupJob]`, an internal Veeam API.

* **Checked on**: VBR 12.3.
* **Type cannot be read**: for example, if a VBR 13 build does not load the type in PowerShell 7. A server with such policies is then refused before anything changes.

### Windows Script Host: registry setting only

The script handles the `Enabled` values Veeam KB4699 names.

An application-control policy (AppLocker, WDAC or Software Restriction Policies) that blocks `wscript.exe` or `cscript.exe` is not detected. Such a policy would still make the installer fail. See [Windows Script Host](windows-script-host.md).

### Pilot first

VB365 support needs VB365 8.6 or later. The unit tests pass on both PowerShell editions.

> [!IMPORTANT]
> Pilot each new product, version and PowerShell edition on one non-production server before fleet rollout.

[Back to the README](../README.md) · [All docs](README.md)
