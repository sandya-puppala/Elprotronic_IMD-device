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
FPA-1 20220147 TYPE-IMOTION
```

> **The `TYPE-` token is case-sensitive and must be exactly `IMOTION`.**
> `Generic-FPA.h:117` defines `IMOTION_DLL_TYPE = "IMOTION"`. The full token
> table (`Generic-FPA.h:108-118`) is: `C2000`, `CC`, `CC-GP`, `ARM`, `ARM-GP`,
> `MSP`, `MSP-GP`, `M`, `M-GP`, `IMOTION`, `IMOTION-GP` — all uppercase.
> A mistyped token (`TYPE-iMOTION`) does **not** fail loudly: the server still
> starts and opens the adapter, but falls back to the **ARM** DLL, which has
> `COMM_UART` disabled (`comm_definitions.h:16` — `//not supported a.t.m.`).
> `AutoProgram` then dies with *"Selected communication is not supported"*
> because the cfg's `Interface 514` = `COMM_UART | COMM_FAST`. Use `IMOTION`.

### 3.3 Working `.cfg` — DONE

Two files:

- **`C:\Users\Sandhya\Desktop\MCE11.CFG`** — exported as-is from the v1.05
  FlashPro-iMOTION GUI. Reference / source of truth.
- **`C:\Elprotronic\imd111t-cli.cfg`** — the one the batch file actually uses.
  Identical to `MCE11.CFG` except `PromptForPowerCycle` and
  `PromptForFirstPageErase_coreM0only` are set to `0` so `AutoProgram` runs
  fully unattended (see §11, 11:21 entry, for why).

Verified `MCE11.CFG` contents:

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

## 6. The batch file — `C:\Elprotronic\flash-imd111t.bat`

**Always use this rather than hand-typing client commands.** The `-m` flag
concatenates everything after it *on the same line*; if the file-path argument
wraps onto a second prompt line, the server receives a bare command with no
argument and returns an error (observed: `ConfigFileLoad` with no path →
`RETURN: 535`). A batch file eliminates that class of mistake entirely.

Prerequisite — server already running in its own window:

```
cd "C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64"
Generic-CommandLine-Server.exe FPAs-setup.ini -b
```

Then, in any other `cmd` window:

```
C:\Elprotronic\flash-imd111t.bat classb-en
C:\Elprotronic\flash-imd111t.bat working
C:\Elprotronic\flash-imd111t.bat recover
C:\Elprotronic\flash-imd111t.bat "C:\path\to\some.ldf"
```

| Argument | Action |
|---|---|
| `classb-en` | Program `Not_Working_ClassB_enabled_I2Cdisable.ldf` — the file the v3.02 GUI fails on. No mass-erase. |
| `working` | Mass-erase, then program `Working_ClassB_disabled_I2Cdisable.ldf` — recovers comms on a bricked chip. |
| `recover` | Mass-erase, program firmware `V5.03.00`, then program Working params — full recovery. |
| `"<path.ldf>"` | Program an arbitrary `.ldf` as-is (cfg loaded, no erase). |

The `.ldf` files were copied out of the space-laden `Downloads\IMD111T Demo test
files\...` path into `C:\Elprotronic\imd111t-ldf\` so no path needs quoting
gymnastics. The cfg path (`C:\Users\Sandhya\Desktop\MCE11.CFG`) and FPA index
(`1`) are baked into the batch file — edit the `set` lines at the top to change.

## 7. Reading the result — exit codes vs. RETURN codes

**`CommandLine-Client.exe` does NOT propagate the programming result.** Per
`Pipe-Client.cpp`, the client returns `0` on any successful pipe round-trip and
`-1` only on a pipe failure (server not running). It does **not** return the
server's status. So `errorlevel` / `$LASTEXITCODE` only tells you "did the
client reach the server", never "did programming pass".

The authoritative result is the server's `RETURN:` line, printed to stdout by
both the server console and the client:

```
[14/May/2026:10:43:46] (1) RETURN: 1     <- step PASSED
[14/May/2026:10:43:46] (1) RETURN: 535   <- step FAILED (here: no/invalid cfg file)
```

`RETURN: 1` = pass. Any other value on `ConfigFileLoad` / `ReadCodeFile` /
`AutoProgram` / `Memory_Erase` is a failure — read the `INFO:` / `ERROR:` lines
around it, and run `Report_Message` for the full GUI-style log.

Because the result isn't a process exit code, automation (Phase 4) must **parse
the `RETURN:` token out of stdout** rather than checking `errorlevel`.

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `AutoProgram` → *"Selected communication is not supported"* | `FPAs-setup.ini` token mistyped — server fell back to the ARM DLL, which has `COMM_UART` disabled | Token must be exactly `TYPE-IMOTION` (uppercase). Fix the `.ini`, restart the server |
| `RETURN: 535` on `ConfigFileLoad` | Command sent with no path (line wrapped) | Use the batch file; never hand-type |
| Client prints `Could not open pipe` | Server not running | Start `Generic-CommandLine-Server.exe FPAs-setup.ini -b` first |
| `INIT: Found 0 adapters` | Wrong serial in `FPAs-setup.ini`, or adapter unplugged | Confirm serial `20220147`, replug USB |
| `AutoProgram` fails on a freshly bricked chip | USB scheduling drifted through the catch-at-startup window | Re-run: `flash-imd111t.bat working` (it mass-erases first) |
| `AutoProgram` still fails after retry | Vcc not collapsing below SBSL reset threshold | Re-export cfg with `PowerCycleVccOff` raised to `500` ms |
| Server blocks on a dialog | `PromptForPowerCycle 1` triggered (only if FPA not powering target) | Re-export cfg with `PromptForPowerCycle 0` |

## 9. Source references (all on this machine)

- `C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64\README.txt` — confirms bundled v1.04 iMOTION API DLL
- `C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64\sequence.txt` — canonical command sequence
- `C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64\FPAs-setup.ini` — setup.ini format
- `C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64\STM32H750VB-Issi-ext.cfg` — `.cfg` field reference
- `C:\Elprotronic\Generic-FPA-DLLs (x64)\CommandLine-Client\Pipe-Client.cpp` — client flag semantics
- `C:\Elprotronic\Generic-FPA-DLLs (x64)\Generic-BatchFile-Demo-4.5.2\Generic-BatchFile-Demo.cpp` — full API surface
- `C:\Program Files (x86)\Elprotronic\iMOTION\API-DLL\FP-iMOTION-Demo-C++\FP-iMOTION-MultiDll-DemoDlg.cpp` — iMOTION uses FlashPro-ARM API surface
- `C:\Program Files (x86)\Elprotronic\FP-GP-X (x86)\History-X.txt` — confirms v3.02 release dates
- Elprotronic wiki Getting-Started: <https://elprotronic.atlassian.net/wiki/spaces/FPGPARM/pages/36962323/Generic+DLL+CLI+Getting+Started>

## 10. Status

| Item | State |
|---|---|
| Generic-FPA install tree present | confirmed |
| v1.04 iMOTION API DLL in `bin\x64` | confirmed (May 13 2024, 16 MB) |
| `FPAs-setup.ini` populated with FPA serial `20220147` | **done** |
| Working `.cfg` (`C:\Users\Sandhya\Desktop\MCE11.CFG`) | **done — verified IMD111T-6F040, UART, FPA-powered** |
| Server starts, finds adapter | **done — `SN=20220147`, `HW PN=XStream-I-1.1`, Full Access** |
| `.ldf` files copied to `C:\Elprotronic\imd111t-ldf\` | **done** |
| `flash-imd111t.bat` written to `C:\Elprotronic\` | **done** |
| `FPAs-setup.ini` token corrected to `TYPE-IMOTION` | **done — was `TYPE-iMOTION`, caused ARM-DLL fallback** |
| DLL `VersionInfo` check (§3.4) | pending — run the PowerShell one-liner *in PowerShell, not cmd* |
| Phase 3a — program Class-B-**enabled** `.ldf` (`classb-en`) | **DONE — PASS, see §11** |
| Phase 3b — reprogram a chip that already holds Class-B params | **in progress** — first try failed (no headless power-cycle); cfg fixed, retest pending |
| `imd111t-cli.cfg` (prompts disabled) | **done** — batch file now points here |
| Phase 4 `elprotronic-fpa` backend in `flash-mce.py` | pending — must parse `RETURN:` from stdout, not exit code |

## 11. Bench results log

### 2026-05-14 11:14 — `flash-imd111t.bat classb-en` — PASS

First successful CLI programming run. After correcting the `FPAs-setup.ini`
token to `TYPE-IMOTION` and restarting the server:

| Step | `RETURN:` |
|---|---|
| `ConfigFileLoad C:\Users\Sandhya\Desktop\MCE11.CFG` | `1` |
| `ReadCodeFile …\Not_Working_ClassB_enabled_I2Cdisable.ldf` | `1` |
| `AutoProgram 0` | `1` (6.4 s) |
| `Report_Message` | PASS |

`Report_Message` output:

```
MCE UART speed (  115.2 kb/s).
MCE UART communication - CONF (115.2 kb/s).
Communication initialization.........    OK
Erasing memory ...............................   done
Flash programming .................
MCE UART speed (   57.6 kb/s).
MCE UART speed ( 2100.0 kb/s).
MCE UART speed (  115.2 kb/s).
...      OK
 -------- D O N E --- ( run time =   6.4 sec.)
```

**Significance:** the Class-B-enabled parameter file — the exact file the v3.02
unified GUI cannot program — went through cleanly via the Generic-FPA CLI route
on the v1.04 iMOTION DLL. The 115.2 → 57.6 → 2100 → 115.2 kb/s baud sequence is
the SBSL catch-at-startup / auto-baud handshake working as it does under the
v1.05 GUI. Option C is validated for *programming* Class-B params.

**Still to confirm (Phase 3b):** the original pain point is *reprogramming a
chip that already holds Class-B-enabled params*. The chip is now in exactly that
state, so the next run — `flash-imd111t.bat working` — is the real recovery
test: it must establish comms with the Class-B-loaded chip, mass-erase, and
program the Working params.

### 2026-05-14 11:21 — `flash-imd111t.bat working` — FAIL → cfg fix applied

With the chip now holding Class-B-enabled params from the 11:14 run (i.e. the
real bricked state), the recovery run failed:

| Step | `RETURN:` |
|---|---|
| `ConfigFileLoad` | `1` |
| `Memory_Erase 0` | `0` (failed, ~24 s) |
| `ReadCodeFile …\Working_ClassB_disabled_I2Cdisable.ldf` | `1` |
| `AutoProgram 0` | `0` (failed, ~23 s) |
| `Report_Message` | FAILED |

`Report_Message` output:

```
MCE UART speed (  115.2 kb/s).
MCE UART speed (  115.2 kb/s).
MCE UART speed (  115.2 kb/s).
MCE UART speed (  115.2 kb/s).
Communication initialization.........    failed
 --------------- FAILED !!! -----------------
```

**Diagnosis.** Four retries at the running-app baud (115.2 kb/s), never
dropping to the 57.6 kb/s SBSL catch-at-startup baud. The chip's MCE app is in
the Class-B safe-fault loop, so nothing answers at 115.2 — `AutoProgram` needs
to **power-cycle the target and catch the SBSL at startup**, and it didn't.

Root cause: `MCE11.CFG` has `PromptForPowerCycle 1`. In the v1.05 GUI a human
acknowledges that dialog; headless, the server can't show it, so `AutoProgram`
never performs the power cycle and just exhausts its running-app retries.

A separate `Power_Target 0/1` CLI command pair can't substitute — the SBSL
catch-at-startup window is only ~100 ms after power-on, far shorter than the
client/pipe round-trip between CLI calls. The power cycle **must** happen
inside `AutoProgram`, which means the cfg must let it run unattended.

**Fix applied.** `C:\Elprotronic\imd111t-cli.cfg` — a copy of `MCE11.CFG` with:

| Key | `MCE11.CFG` | `imd111t-cli.cfg` |
|---|---|---|
| `PromptForPowerCycle` | `1` | `0` |
| `PromptForFirstPageErase_coreM0only` | `1` | `0` |

`PowerFromFpaEn` stays `1` — the FPA owns Vcc, so with the prompt disabled
`AutoProgram` can power-cycle the target itself. `flash-imd111t.bat` now points
`CFG` at `imd111t-cli.cfg`. Retest pending.
