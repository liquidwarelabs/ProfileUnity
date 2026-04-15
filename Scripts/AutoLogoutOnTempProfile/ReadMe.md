# LogoffIfTemp.ps1 — Help & Reference

## Overview

`LogoffIfTemp.ps1` is a PowerShell script that detects whether the currently logged-in user is running under a **temporary Windows profile** and, if so, safely logs them off. It also performs cleanup of Group Policy logoff scripts — specifically those associated with **Liquidware ProfileUnity** — to prevent those scripts from firing during the logoff of a temporary session.

**Requires:** PowerShell 5.0 or later

---

## Why This Script Exists

Windows creates a temporary profile when it cannot load a user's normal profile (e.g., due to a corrupted profile, a locked profile folder, or a rights issue). Users working in a temporary profile may lose their work and settings. This script gives administrators a way to automatically detect and terminate those sessions early, reducing confusion and data loss.

Additionally, Liquidware ProfileUnity registers a logoff script (`LwL.ProfileUnity.Client.Logoff.exe`) via Group Policy. Running this script against a temporary profile can cause errors or unintended behavior, so the script removes those registry entries before initiating logoff.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Force` | Switch | No | Skips the 5-second countdown and confirmation prompt; logs off immediately upon detecting a temporary profile. |
| `-LogPath` | String | No | Full path to a custom log file. If omitted, a timestamped log is created automatically in the user's `%TEMP%` directory. |

---

## Usage Examples

**Basic check — log off if temporary profile detected:**
```powershell
.\LogoffIfTemp.ps1
```

**Force immediate logoff with no delay:**
```powershell
.\LogoffIfTemp.ps1 -Force
```

**Write log output to a specific file:**
```powershell
.\LogoffIfTemp.ps1 -LogPath "C:\Logs\LogoffIfTemp.log"
```

**Combine Force and a custom log path:**
```powershell
.\LogoffIfTemp.ps1 -Force -LogPath "C:\Logs\LogoffIfTemp.log"
```

---

## What the Script Does

The script executes in the following order:

**1. Logging Setup**
Creates a log file at the path specified by `-LogPath`, or auto-generates one at `%TEMP%\LogoffIfTemp_<timestamp>.log`. All key actions are written to both the console and the log file.

**2. Temporary Profile Detection**
Reads the current user's SID and checks the Windows registry (`HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\<SID>`) for three indicators of a temporary profile:

- The `ProfileImagePath` value contains `Temp`, `.tmp`, or `Temporary`
- The profile `State` value equals `0x200` (512 decimal), which Windows uses to flag temporary profiles
- The `USERPROFILE` environment variable doesn't match the registry path and the registry path contains `Temp`

**3. Group Policy Logoff Script Removal**
Regardless of whether a temporary profile is detected, the script scans and removes logoff script entries from multiple registry locations under both `HKU:\<SID>` and `HKCU:`:

- `...\Group Policy\Scripts\Logoff`
- `...\Policies\Microsoft\Windows\System\Scripts\Logoff`
- `...\Group Policy\History`

It also clears Group Policy script execution state timestamps and sets `DisableLogoffScripts = 1` in the registry to block any remaining logoff scripts from executing.

**4. ProfileUnity Process Termination** *(only if temporary profile detected)*
Before initiating logoff, the script searches for and kills any running instances of `LwL.ProfileUnity.Client.Logoff.exe` that belong to the current user, using WMI to verify process ownership.

**5. Logoff**
If a temporary profile was detected:
- Without `-Force`: displays a 5-second countdown (can be cancelled with `Ctrl+C`), then re-checks for ProfileUnity processes before proceeding.
- With `-Force`: logs off immediately.

Logoff is performed via `shutdown.exe /l /f` (force local logoff), which works across all supported Windows versions.

If no temporary profile is detected, the script exits cleanly with no action taken (use `-Verbose` to see a confirmation message).

---

## Log Output

Every run produces a log file with timestamped entries. Example:

```
[2026-04-15 09:32:01] [INFO] === LogoffIfTemp Script Started ===
[2026-04-15 09:32:01] [INFO] Current user SID: S-1-5-21-...
[2026-04-15 09:32:02] [INFO] Normal profile detected. No action required.
[2026-04-15 09:32:02] [INFO] === LogoffIfTemp Script Completed ===
```

The log file path is printed to the console at the start of each run.

---

## Registry Locations Modified

| Path | Action |
|---|---|
| `HKU:\<SID>\...\Group Policy\Scripts\Logoff` | Removed (entire key tree) |
| `HKCU:\...\Group Policy\Scripts\Logoff` | Removed (entire key tree) |
| `HKU:\<SID>\...\Policies\Microsoft\Windows\System\Scripts\Logoff` | Removed if present |
| `HKCU:\...\Policies\Microsoft\Windows\System\Scripts\Logoff` | Removed if present |
| `HKU:\<SID>\...\Group Policy\History` | Removed if present |
| `HKCU:\...\Group Policy\History` | Removed if present |
| `HKU:\<SID>\...\Policies\Microsoft\Windows\System\Scripts` | Sets `DisableLogoffScripts = 1` |
| `HKCU:\...\Policies\Microsoft\Windows\System\Scripts` | Sets `DisableLogoffScripts = 1` |

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Script completed successfully (profile normal or logoff initiated) |
| `1` | Profile registry key not found, or logoff command failed |

---

## Notes & Considerations

- The script runs in the context of the **currently logged-in user** and does not require elevation beyond what is needed to read the profile registry key and remove Group Policy entries under that user's hive.
- Group Policy logoff script cleanup runs **every time** the script is invoked, not only when a temporary profile is detected. This ensures ProfileUnity scripts are cleared even if profile detection is inconclusive.
- The `shutdown.exe /l /f` command initiates a **forced local logoff** and cannot be undone once called.
- If the script is deployed via Group Policy or a login/startup mechanism, pair it with `-Force` to avoid the interactive countdown.