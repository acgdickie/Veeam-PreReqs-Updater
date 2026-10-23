# Windows Script Host and Veeam hardening

This page explains how the script handles Windows Script Host (WSH) on a hardened Veeam server, and what each `WshStatus` value means. Read it when a report shows a `WshStatus` value or a WSH issue code.

**In short**

* **Automatic:** the script turns WSH on for the PostgreSQL installer and off again afterwards, as Veeam KB4699 describes. A hardened server needs no extra step.
* **Short window:** WSH is on for the minutes the installer runs, not for the whole run.
* **Audit changes nothing:** an audit reports `WshStatus=DISABLED` and carries on.
* **Exit `20`:** the run stops with `WSH_NOT_WRITABLE` if WSH is off and this account cannot change it, or with `WSH_ENABLE_FAILED` if it cannot turn WSH on.
* **Exit `40`:** `WshStatus=LEFT_ON` means WSH is still on. `ActionRequired` gives the command, as in KB4699.

## Why the script touches WSH

Veeam's Security & Compliance Analyzer advises turning Windows Script Host (WSH) off. The PostgreSQL installer needs it. Without it, the install fails part-way (Veeam KB4698).

Veeam's answer is to turn WSH on for the install and off again afterwards, with no restart (Veeam KB4699). The script does exactly that, so a hardened server needs no extra step.

## What happens at each point

* **An audit** reports `WshStatus=DISABLED` and carries on. It changes nothing.
* **STEP 9** (audit and `-Install`): if WSH is off, checks that this account can change the setting. If it cannot, the run stops there with exit `20` (`WSH_NOT_WRITABLE`), before anything changes.
* **`-Install`** reads the `Enabled` values again in STEP 17, just before the installer starts. Then it:
  1. saves each value that turns WSH off (key, type and data) in the run's `recovery-state.json`
  2. deletes it, as KB4699 does
  3. checks that WSH is on
* **If those steps fail**, the installer never starts. The values are put back and the run rolls back (`WSH_ENABLE_FAILED`, exit `20`).
* **As soon as the installer exits**, whatever its result, the script writes each saved value back with its exact type and data. Then it checks each value (`WshStatus=RESTORED`). WSH is on for the minutes the installer runs, not for the whole run.
* **If the run stops before the values are written back**, the end of the run puts the values back.
* **A run that is killed outright** (for example by an RMM timeout) leaves WSH on. `-Recover` puts it back.
* **While the installer is still running** (`INSTALLER_TIMEOUT`), WSH stays on, because turning it off would break the installer. `-Recover` turns it off once the installer has gone.
* **`-Reboot`** books no restart while WSH is still on.

See [Exit codes](exit-codes.md) for exit `20` and `40`, and [How it works](how-it-works.md) for STEP 9 and STEP 17.

## The two registry values

The script changes only the two values KB4699 names. It changes them for the account it runs as (SYSTEM under an RMM):

* `HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings`, value `Enabled`
* that account's `HKCU:\Software\Microsoft\Windows Script Host\Settings`, value `Enabled`

For the `HKCU` value:

* **Recorded path:** the script records it as `Registry::HKEY_USERS\<SID>\Software\...`.
* **Right account:** because of that, a `-Recover` run as another account, and the command in `ActionRequired`, still change the right account's value.
* **Profile not loaded:** an account whose profile is not loaded uses `HKEY_USERS\.DEFAULT` instead, as Windows does. For SYSTEM, `S-1-5-18` is `.DEFAULT`.

A value that already holds the saved type and data is left alone. So the script never reports a value it did not change as turned off again.

## WshStatus values

| `WshStatus` | Meaning |
|---|---|
| (empty) | The run ended before STEP 9 or took the NATS path. On `-Recover`, see the notes below |
| `ENABLED` | WSH was on. Nothing to do |
| `DISABLED` | WSH is off. An audit reports it; `-Install` turns it on for the installer only |
| `RESTORED` | The run turned WSH on for the installer, then turned it off again, exactly as before |
| `LEFT_ON` | The run turned WSH on and could not turn it off again, or the installer is still running. Exit `40` |

Notes on the table:

* **(empty) on `-Recover`:** the interrupted run had not changed WSH, or had already put it back, or `-Recover` refused the marker or its state. In that last case, read `WshOriginalValues` and `WshRestored` in its `recovery-state.json`.
* **`DISABLED` after `-Install`:** an `-Install` run that stopped before STEP 17 also reports it.
* **`LEFT_ON`:** `ActionRequired` gives the command, as in KB4699.

For more on the NATS path, see [Updating NATS (VB365)](nats.md). For `recovery-state.json`, see [Logs, backups and evidence](evidence.md).

## Running the installer by hand

To run the PostgreSQL installer by hand on a hardened server, turn WSH on first, as KB4699 describes, and off again afterwards.

[Back to the README](../README.md) · [All docs](README.md)
