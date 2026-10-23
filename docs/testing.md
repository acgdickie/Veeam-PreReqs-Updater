# Testing (for people who change the script)

This page explains `Test-Helpers.ps1`, the tests for `Update-VeeamPreReqs.ps1`, and you read it when you change the script.

**In short**

* **Never** copy `Test-Helpers.ps1` to a Veeam server or add it to the RMM.
* **Run it** after every change to the script and before every push.
* **Both editions**: run it under `powershell.exe` and `pwsh.exe`.
* **Elevated only**: a run that is not elevated is never a pass.
* **A pass** ends with `RESULT: <n> passed, 0 failed` and exit code `0`.

## Why `Test-Helpers.ps1` is there

`Test-Helpers.ps1` is the safety net for changes to `Update-VeeamPreReqs.ps1`. It is for whoever edits the script. It is for testing only.

> [!IMPORTANT]
> Never copy `Test-Helpers.ps1` to a Veeam server or add it to the RMM.

The update needs only `Update-VeeamPreReqs.ps1`. The settings are built into the script, so an RMM that uploads just the one file to a temp folder works.

## How to run it

Run the tests any time:

```bash
powershell -ExecutionPolicy Bypass -File .\Test-Helpers.ps1
```

Run it after every change to the script and before every push. Run it:

* from an elevated prompt. See "Always run it elevated" below.
* in the project folder.
* on both editions: `powershell.exe` and `pwsh.exe`. The two editions behave differently, and both are supported.

Run it in each edition:

```bash
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Test-Helpers.ps1
```

```bash
pwsh.exe -ExecutionPolicy Bypass -NoProfile -File .\Test-Helpers.ps1
```

### Read the result

* **Pass**: the run ends with `RESULT: <n> passed, 0 failed` and exit code `0`.
* **`FAIL` lines**: each `FAIL` line names the rule that broke.

### Always run it elevated

A run that is not elevated is never a pass. Without elevation:

* **Folder-lock checks** are skipped. You see one `SKIP  not elevated` line.
* **Many `-Recover` checks** fail. Their throw-away work folders cannot be locked to SYSTEM and Administrators.
* **Exit code** is `1`.

## What it does

### Runs the shipped code

The checks read the real functions out of `Update-VeeamPreReqs.ps1` with the PowerShell parser, and run them. They do not use a copy. So the function tests always run the shipped code.

### Main part: read, not run

The main part of the script (STEP 1 to STEP 21) is not run, with one exception. One elevated check starts the real script against an unsafe folder and expects it to refuse (exit `20`).

The rest of the main part is checked by reading its text and structure. That catches changed wording and order, but not every change in behaviour.

### Fakes and real calls

`Test-Helpers.ps1` fakes:

* Veeam cmdlets.
* Service and process changes: every call that would change a service or a process (`Start-Service`, `Stop-Service`, `Stop-Process`, `sc.exe`).

It needs no Veeam, no PostgreSQL and no network.

A few harmless real calls remain:

* `Get-Process` and `Get-Service` lookups.
* `cmd.exe`.
* `reg.exe`.
* One elevated run of the real script.

### Throw-away items

It creates only throw-away items, named with its process ID:

* Folders under `%TEMP%` and `C:\vpgu-wr-test-<PID>`.
* One `.reg` file under `%TEMP%`.
* Three registry keys under `HKCU:\Software`.

It removes them all again. It never writes the real Windows Script Host keys.

### Enterprise Manager tool check

It also tests the configuration backup check in `Clear-StaleEnterpriseManagerRecord.ps1`, the same way. It reads that function out of the tool and runs it against a fake Veeam. See [the separate tool](enterprise-manager.md#the-separate-tool-clear-staleenterprisemanagerrecordps1).

### Rules that must always hold

It also checks rules that must always hold, by reading the script itself. For example:

* **Services**: the script never force-stops a service.
* **`Stop-Process`**: the script uses it only to close a Veeam console.
* **Audit run**: an audit run never closes a console.
* **Configuration backup**: it is never retried more than once.

## Why both editions matter

VBR 12 runs on Windows PowerShell 5.1 and VBR 13 on PowerShell 7. Some bugs appear on one edition only. A production server is the most expensive place to find one.

So the tests cover both editions. For example:

* **Installer exit code**: Windows PowerShell 5.1 can lose it. That would stop a good install part-way through, with Veeam down.
* **JSON lists**: Windows PowerShell 5.1 reads a JSON list as one nested list. That would stop `-Recover` reading its own job and service records.
* **Folder locking**: it can fail silently on PowerShell 7.

[Back to the README](../README.md) · [All docs](README.md)
