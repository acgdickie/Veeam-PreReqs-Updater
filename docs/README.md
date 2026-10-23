# Documentation

The full detail behind the [README](../README.md). Each page covers one topic and starts with
a short summary.

## Pages

| Page | Read it when |
|---|---|
| [How it works](how-it-works.md) | You want every step, and why it is there |
| [Exit codes and report fields](exit-codes.md) | You set up RMM alerts, or read a result |
| [Parameters and settings](settings.md) | You need a switch or a built-in setting |
| [Running it from an RMM, and rebooting](running-from-an-rmm.md) | You plan a rollout, or use `-Reboot` |
| [NATS updates (VB365)](nats.md) | You look after VB365 servers |
| [Windows Script Host and Veeam hardening](windows-script-host.md) | Your servers follow Veeam's hardening advice |
| [Logs, backups and evidence](evidence.md) | You need a log or a backup, or want to know what is kept |
| [If it goes wrong](troubleshooting.md) | A run returned `40` or `50`, or was interrupted |
| [Enterprise Manager and leftover records](enterprise-manager.md) | Enterprise Manager is, or was, installed |
| [Scope and known limits](scope-and-limits.md) | A server returned `11`, or you want the full rules |
| [Testing](testing.md) | You change the script |

The history of changes is in [CHANGELOG.md](../CHANGELOG.md).

## Words used

| Word | Meaning |
|---|---|
| VBR | Veeam Backup & Replication |
| VB365 / VBM | Veeam Backup for Microsoft 365 |
| NATS | The message server VB365 8 uses for its job queue |
| RMM | Remote monitoring and management tool, which runs the script on each server |
| EOL | End-of-life: a PostgreSQL major version that no longer gets updates |
| Minor update | A move within one major version, for example 15.2 to the latest 15.x |
| Major upgrade | A move to another major version, for example 15 to 16. The script never does this |
| WorkRoot | The script's own folder for logs and backups. Default: `C:\ProgramData\VeeamPgUpdate` |
| Audit | A run without `-Install`. It checks and reports, and changes nothing |

[Back to the README](../README.md)
