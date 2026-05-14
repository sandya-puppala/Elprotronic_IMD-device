# CLI programming runbook — Class-B-enabled IMD111T-6F040 via Generic-FPA DLL

Target audience: bench engineer who has the Elprotronic XStream-Iso adapter wired to
an IMD111T-6F040 over UART, has FlashPro-iMOTION v1.05 installed (working) **and**
the v3.02 unified GUI installed (broken on Class-B-enabled parameter files).

This runbook replaces GUI clicks with a scriptable command-line flow that drives the
**v1.04 iMOTION API DLL** directly, bypassing the v3.02 open-target regression.

It pairs with [`option-c-elprotronic-fpa-plan.md`](../option-c-elprotronic-fpa-plan.md)
— that document is the plan; this one is the operational procedure.

---

## 1. The three install trees, and why only one matters

| Folder | Bitness | Role here |
|---|---|---|
| `C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64\` | x64 | **The CLI route.** Self-contained: `CommandLine-Client.exe`, `Generic-CommandLine-Server.exe`, `Generic-FPA.DLL`, `FlashProiMOTION-FPA1.dll` (May 13 2024, 16 MB — labelled v1.04 in bundled `README.txt`). |
| `C:\Program Files (x86)\Elprotronic\iMOTION\API-DLL\` | x86 (win32) | Standalone 32-bit iMOTION API kit with its own `FlashProiMOTION-FPA1.dll` (Jul 11 2024). **Do not mix into the x64 server** — bitness mismatch. |
| `C:\Program Files (x86)\Elprotronic\FP-GP-X (x86)\` | x86 | The **v3.02 unified GUI** (`FlashPro-X.exe`, `GangPro-X.exe`). `History-X.txt` ends "1-May-2026, version 3.02 updates". **This is the regression — stay away for Class-B work.** |

The Generic-FPA pipeline loads its own bundled v1.04 iMOTION DLL, so v3.02's broken
open-target sequence is never invoked. That is the entire trick.

## 2. Pipeline architecture

```
CommandLine-Client.exe          → named pipe \\.\pipe\elprotronic
   │   one-shot: -i <idx> -m <cmd ...>
   ▼
Generic-CommandLine-Server.exe  (reads FPAs-setup.ini, loads Generic-FPA.DLL)
   │
   ▼
Generic-FPA.DLL                 (dispatches by TYPE-<...> token in the .ini)
   │   TYPE-iMOTION → loads:
   ▼
FlashProiMOTION-FPA1.dll  v1.04 (the working iMOTION programmer)
   │
   ▼
XStream-Iso adapter → IMD111T-6F040 UART
```

`CommandLine-Client.exe` flags (from `Pipe-Client.cpp:97-104`):

| Flag | Meaning |
|---|---|
| `-p <pipename>` | Custom named pipe. Default `\\.\pipe\elprotronic`. |
| `-i <1..64>` | FPA index (which adapter, per `FPAs-setup.ini`). |
| `-m <command + params>` | One-shot command. **Must be last.** Everything after is concatenated into the message. |
| `-configtest` | Echo settings, don't execute. Useful for verifying flag parsing. |

Server commands (case-insensitive) — confirmed via `sequence.txt` and the
`Generic-BatchFile-Demo.cpp` enum at line 549-566:

| Command | API call | Purpose |
|---|---|---|
| `ConfigFileLoad <path.cfg>` | `F_ConfigFileLoad` | Load a setup `.cfg` (MCU type, UART iface, Vcc, power-cycle timing) |
| `ReadCodeFile <path.ldf>` | `F_ReadCodeFile` | Load code/parameter image into FPA buffer |
| `Memory_Erase 0` | `F_Memory_Erase(0)` | Mass-erase MCE flash — **Class-B brick eraser** |
| `Memory_Blank_Check` | `F_Memory_Blank_Check` | Verify blank |
| `AutoProgram 0` | `F_AutoProgram(0)` | Power-cycle → SBSL connect → erase → program → verify |
| `Memory_Write 0` | `F_Memory_Write(0)` | Write only |
| `Memory_Verify 0` | `F_Memory_Verify(0)` | Verify against buffer |
| `Report_Message` | `F_ReportMessage` | Print GUI-style log of last op |
| `Open_Target_Device` / `Close_Target_Device` | — | Open/close target for step ops |

## 3. One-time setup (~15 minutes)

### 3.1 FPA serial number — DONE

XStream-Iso adapter serial: **`20220147`**.

### 3.2 `FPAs-setup.ini` — DONE

`C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64\FPAs-setup.ini` now contains a
single line (stale `TYPE-MSP` / `TYPE-ARM` lines removed):

```
FPA-1 20220147 TYPE-iMOTION
```

### 3.3 Working `.cfg` — DONE

`C:\Users\Sandhya\Desktop\MCE11.CFG`, exported from the v1.05 FlashPro-iMOTION GUI.
Verified contents:

| Key | Value | Meaning |
|---|---|---|
| `MCU_name` | `IMD111T-6F040` | Correct target part |
| `Interface` | `514` | UART interface |
| `PowerFromFpaEn` | `1` | FPA sources Vcc — power cycle is automatic |
| `PowerCycleVccOff` | `300` | Vcc held off 300 ms during power cycle |
| `PowerCycleDelay` | `100` | 100 ms settle after Vcc returns |
| `VccFromFPAin_mV` | `3300` | 3.3 V target rail |
| `FlashEraseModeIndex` | `2` | Mass-erase mode |
| `PromptForPowerCycle` | `1` | See note below |

> **Note on `PromptForPowerCycle 1`:** this only pops a dialog when the FPA does
> *not* own Vcc. Here `PowerFromFpaEn=1`, so the adapter power-cycles the target
> itself and the prompt is bypassed — matches the automatic behaviour you see in
> the v1.05 GUI. If the server ever blocks waiting on a prompt, re-export the cfg
> with `PromptForPowerCycle` set to `0`.

### 3.4 Confirm DLL version — pending

```powershell
(Get-Item "C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64\FlashProiMOTION-FPA1.dll").VersionInfo |
  Select-Object FileVersion, ProductVersion, FileDescription
```

Expect a 1.04-class version. If you ever see ≥ 1.10, that's the v3.02 lineage —
restore the v1.04 DLL from a v1.05 install backup.

## 4. Programming sequence — two consoles

### Console A — server (leave running)

```powershell
cd "C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64"
.\Generic-CommandLine-Server.exe FPAs-setup.ini -b
```

`-b` = background mode; server listens on `\\.\pipe\elprotronic`. The startup log
should name `FlashProiMOTION-FPA1.dll` and show its version.

### Console B — client one-shots

```powershell
cd "C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64"
```

#### Case 1 — chip is Class-B-bricked; flash a Working .ldf to recover comms

```powershell
.\CommandLine-Client.exe -i 1 -m ConfigFileLoad "C:\Users\Sandhya\Desktop\MCE11.CFG"
.\CommandLine-Client.exe -i 1 -m ReadCodeFile  "C:\Users\Sandhya\Downloads\IMD111T Demo test files\IMD111T Demo test files\IMD111T-F040_A_V5.03.00 Mainfirmware shared by infineon.ldf"
.\CommandLine-Client.exe -i 1 -m Memory_Erase 0
.\CommandLine-Client.exe -i 1 -m AutoProgram 0
.\CommandLine-Client.exe -i 1 -m Report_Message
```

Then load Working parameters:

```powershell
.\CommandLine-Client.exe -i 1 -m ReadCodeFile  "C:\Users\Sandhya\Downloads\IMD111T Demo test files\IMD111T Demo test files\Working_ClassB_disabled_I2Cdisable.ldf"
.\CommandLine-Client.exe -i 1 -m AutoProgram 0
.\CommandLine-Client.exe -i 1 -m Report_Message
```

#### Case 2 — chip is alive; deliberately program Class-B-enabled production parameters

```powershell
.\CommandLine-Client.exe -i 1 -m ConfigFileLoad "C:\Users\Sandhya\Desktop\MCE11.CFG"
.\CommandLine-Client.exe -i 1 -m ReadCodeFile  "C:\Users\Sandhya\Downloads\IMD111T Demo test files\IMD111T Demo test files\Not_Working_ClassB_enabled_I2Cdisable.ldf"
.\CommandLine-Client.exe -i 1 -m AutoProgram 0
.\CommandLine-Client.exe -i 1 -m Report_Message
```

This is the file the v3.02 GUI fails on. v1.04 succeeds.

#### Case 3 — re-program after Class-B parameters are loaded

```powershell
.\CommandLine-Client.exe -i 1 -m ConfigFileLoad "C:\Users\Sandhya\Desktop\MCE11.CFG"
.\CommandLine-Client.exe -i 1 -m ReadCodeFile  "<path>\<new>.ldf"
.\CommandLine-Client.exe -i 1 -m Memory_Erase 0
.\CommandLine-Client.exe -i 1 -m AutoProgram 0
.\CommandLine-Client.exe -i 1 -m Report_Message
```

`Memory_Erase 0` before `AutoProgram` is the linchpin: forces Vcc cycle → SBSL
opens within the catch-at-startup window → mass erase wipes the brick before the
faulty Class-B parameters ever execute.

## 5. Why this works where v3.02 fails

| Step | What v1.04 does | Where v3.02 regressed |
|---|---|---|
| `ConfigFileLoad` | Reads `VccFromFPAin_mV`, `PowerCycleVccOff`, `PowerFromFpaEn`, `PromptForPowerCycle` | v3.02 unified config schema; iMOTION-specific power-cycle entries re-mapped |
| `ReadCodeFile` | Parses `.ldf` `a0 XX` Config-mode commands | Same in both — not the regression |
| `Memory_Erase 0` | Cycles Vcc → opens SBSL at catch-at-startup baud → `a0 22 00 00 00` mass erase | v3.02 tries to open the running app first and times out before falling back |
| `AutoProgram 0` | Reopens target, programs `a0 20`-blocks, verifies `a0 21`-blocks | v3.02's open-target dance is broken on a brick |
| `Report_Message` | Same log content as v1.05 GUI report pane | Diagnostics only |

## 6. Wrapping in a PowerShell script

`flash-imd111t.ps1`:

```powershell
param(
    [Parameter(Mandatory)][string]$Cfg,
    [Parameter(Mandatory)][string]$Ldf,
    [switch]$MassErase
)

$ErrorActionPreference = 'Stop'
$bin = "C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64"
$client = Join-Path $bin "CommandLine-Client.exe"

function Step {
    param([string[]]$Args)
    & $client -i 1 -m @Args
    if ($LASTEXITCODE -ne 0) { throw "step failed: $($Args -join ' ') (rc=$LASTEXITCODE)" }
}

Step ConfigFileLoad $Cfg
Step ReadCodeFile  $Ldf
if ($MassErase) { Step Memory_Erase 0 }
Step AutoProgram 0
Step Report_Message
```

Usage:

```powershell
.\flash-imd111t.ps1 -Cfg C:\Users\Sandhya\Desktop\MCE11.CFG `
                    -Ldf "C:\...\Not_Working_ClassB_enabled_I2Cdisable.ldf" `
                    -MassErase
```

## 7. Error handling

`CommandLine-Client.exe` returns the server's status code. Non-zero on
`AutoProgram` against a freshly bricked chip can happen if USB scheduling drifts
through the catch-at-startup window — retry sequence:

```powershell
Step Memory_Erase 0
Step AutoProgram 0
```

If that still fails:

1. Check `Console A` log — does the server show "FPA opened" with the right serial?
2. Verify Vcc with a meter on the test points — the FPA should be sourcing power
   per `PowerFromFpaEn 1` in the cfg.
3. Increase `PowerCycleVccOff` to `500` (ms) in the cfg, reload via
   `ConfigFileLoad`, retry. Longer Vcc-off ensures rail collapses below SBSL
   reset threshold.

## 8. Source references (all on this machine)

- `C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64\README.txt` — confirms bundled v1.04 iMOTION API DLL
- `C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64\sequence.txt` — canonical command sequence
- `C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64\FPAs-setup.ini` — setup.ini format
- `C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64\STM32H750VB-Issi-ext.cfg` — `.cfg` field reference
- `C:\Elprotronic\Generic-FPA-DLLs (x64)\CommandLine-Client\Pipe-Client.cpp` — client flag semantics
- `C:\Elprotronic\Generic-FPA-DLLs (x64)\Generic-BatchFile-Demo-4.5.2\Generic-BatchFile-Demo.cpp` — full API surface
- `C:\Program Files (x86)\Elprotronic\iMOTION\API-DLL\FP-iMOTION-Demo-C++\FP-iMOTION-MultiDll-DemoDlg.cpp` — iMOTION uses FlashPro-ARM API surface
- `C:\Program Files (x86)\Elprotronic\FP-GP-X (x86)\History-X.txt` — confirms v3.02 release dates
- Elprotronic wiki Getting-Started: <https://elprotronic.atlassian.net/wiki/spaces/FPGPARM/pages/36962323/Generic+DLL+CLI+Getting+Started>

## 9. Status

| Item | State |
|---|---|
| Generic-FPA install tree present | confirmed |
| v1.04 iMOTION API DLL in `bin\x64` | confirmed (May 13 2024, 16 MB) |
| `FPAs-setup.ini` populated with FPA serial `20220147` | **done** |
| Working `.cfg` (`C:\Users\Sandhya\Desktop\MCE11.CFG`) | **done — verified IMD111T-6F040, UART, FPA-powered** |
| DLL `VersionInfo` check (§3.4) | pending — quick PowerShell one-liner |
| Phase 3 manual test (Working → Not_Working → Working) | pending — needs bench session |
| Phase 4 `elprotronic-fpa` backend in `flash-mce.py` | pending |
