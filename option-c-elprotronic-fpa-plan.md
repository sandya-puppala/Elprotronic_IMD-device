# Option C — Drive the Elprotronic adapter via Generic-FPA DLL

Working plan for bypassing the FlashPro-iMOTION v3.02 GUI regression by driving the Elprotronic XStream-Iso adapter directly through Elprotronic's officially-supported Generic-FPA DLL automation interface.

Target consumer: `tam-imotion-flash` repository's `feat/imd111t-mce-only` branch. This document stays here until Phase 3 validation passes; promoted to that repo afterwards.

Date: 2026-05-13

---

## Why this option

**Problem.** Elprotronic FlashPro-iMOTION GUI v3.02 (unified release) introduced a regression that breaks catch-at-startup recovery for IMD111T targets running Class-B-enabled parameters. v1.05 of the same software works correctly. Class B is a customer requirement (IEC 60335-1), so we cannot ship v3.02 behaviour. Vendor support is unresponsive.

**Why Option C over the others.**
- **Option A (keep using v1.05 GUI)** — works today but is operator-clicks-only, can't be integrated into `flash-mce.py`, and is one Windows update away from breaking.
- **Option B (reverse-engineer with logic analyzer)** — definitive but takes days and produces a spec, not a tool.
- **Option C (Generic-FPA DLL automation)** — uses Elprotronic's officially-supported automation interface, routes through whichever FlashPro-iMOTION API-DLL is on the machine (v1.05 if we install Generic-FPA DLL alongside the v1.05 install), and integrates cleanly with `flash-mce.py`.

**What we get from C in one move.**
- Bypass v3.02 regression — automation goes through v1.05's working API-DLL.
- Remove operator GUI step — `flash-mce.py` invokes programming.
- Single tool path for both MCE-mode and Class-B-mode flashing — different backends, same script.
- Future-proof slot for a non-Elprotronic implementation later if desired.

---

## Architecture

```
flash-mce.py  --backend elprotronic-fpa  --param X.ldf
        |
        v  spawn / connect via named pipe
   Generic-CommandLine-Server.exe       (long-running, opens adapters from setup.ini)
        |   issues text commands
        v
   Generic-CommandLine-Client.exe       (one-shot per command, returns text result)
        |   routed by
        v
   Generic-FPA.dll                      (adapter dispatcher)
        |   calls into
        v
   FlashPro-iMOTION API-DLL (v1.05)     <-- KEY: the working version
        |
        v  USB
   XStream-Iso / XStreamPro-Iso adapter
        |  Vcc + UART
        v
   IMD111T on customer fixture
```

The `flash-mce.py` glue is ~150 lines. Most engineering is configuration + validation in Phases 1-3.

---

## Prerequisites

| # | Item | Where to get it | Status |
|---|------|------------------|--------|
| 1 | Generic-FPA DLL v1.72 (zip) | https://content.elprotronic.ca/downloads/Generic-win.zip | TODO download |
| 2 | Generic-FPA DLL User's Guide | https://content.elprotronic.ca/docs/Generic-FPA-DLL-UserGuide.pdf | Pulled, on disk |
| 3 | v1.05 FlashPro-iMOTION installed | Already on Sandhya's machine | Confirmed |
| 4 | XStream-Iso / XStreamPro-Iso adapter SN | Read off the label, or via discovery in Phase 1 | TODO |
| 5 | v1.05 config file (`.cfg`) | Likely `C:\Program Files (x86)\Elprotronic\FlashPro-iMOTION\Configs\*.cfg` or `%LOCALAPPDATA%\Elprotronic\` | TODO locate |
| 6 | Working `.ldf` files | `C:\Users\Sandhya\Downloads\IMD111T Demo test files\IMD111T Demo test files\` | Confirmed |
| 7 | Python 3.x | Already in `tam-imotion-flash/scripts/setup-windows.ps1` | Confirmed |

---

## Phase 1 — sanity-check Generic-FPA DLL on the v1.05 machine

Goal: confirm the DLL sees the adapter and loads the v1.05 API-DLL (not v3.02's). ~15 min.

### Steps

1. Download `Generic-win.zip` from the URL above. Unzip to:
   ```
   C:\Elprotronic\Generic-FPA-DLL\
   ```
   Expect to see: `Generic-FPA.dll`, `Generic-CommandLine-Server.exe`, `Generic-CommandLine-Client.exe`, a `setup.ini` template, README/license.

2. Run discovery mode with verbose level 3:
   ```cmd
   "C:\Elprotronic\Generic-FPA-DLL\Generic-CommandLine-Server.exe" -discovery -v 3
   ```

3. From the verbose output, record:
   - Adapter type reported (should be FlashPro-iMOTION or XStream-Iso).
   - Adapter SN.
   - Path of the API-DLL the server loaded. **This must point at the v1.05 install directory**, not a v3.02 path.

### Decision gate

- If the API-DLL path is **v1.05** → continue to Phase 2 as designed.
- If it's **v3.02** → before Phase 2: either remove v3.02 from PATH, or override the DLL search path so the server finds v1.05 first. Re-run discovery to confirm.

### Deliverable

A text file `phase1-discovery.log` (anywhere local) containing the verbose discovery output.

---

## Phase 2 — capture v1.05 config and write the FPA setup file

Goal: bring v1.05's working configuration under version control. ~30 min.

### Steps

1. Find v1.05's iMOTION config file. Check these locations in order:
   - `C:\Program Files (x86)\Elprotronic\FlashPro-iMOTION\Configs\*.cfg`
   - `%LOCALAPPDATA%\Elprotronic\FlashPro-iMOTION\*.cfg`
   - `%USERPROFILE%\Documents\Elprotronic\*.cfg`
   - The directory the v1.05 GUI's `File > Open Project` dialog defaults to

   Look for a `.cfg` / `.ini` / `.prj` file with iMOTION/IMD111T target settings.

2. Stage the captured config in this repo:
   ```
   configs/imd111t-v105.cfg
   ```

3. Write the FPA setup file:
   ```
   configs/setup.ini
   ```
   Contents (replace `<SN>` with the actual SN from Phase 1):
   ```
   # adapter_index   adapter_type           SN
   1                 FlashPro-iMOTION       <SN>
   ```

4. Sanity check the config file in a plain text editor — confirm it references the IMD111T target and includes the Vcc / baud / catch-startup settings v1.05 was using when it worked.

### Deliverable

Both files committed under `configs/`. These are the "working configuration" snapshot.

---

## Phase 3 — manual command-line programming tests (no Python yet)

Goal: validate the DLL path works end-to-end before writing any wrapper code. ~1 hour at the bench.

### Tests in order

Open **Console A** for the server:
```cmd
"C:\Elprotronic\Generic-FPA-DLL\Generic-CommandLine-Server.exe" ^
   -setup "<path-to-this-repo>\configs\setup.ini" -v 2
```
Leave it running.

Open **Console B** for the client. Test 1 — Working file on a fresh board:
```cmd
set CLIENT="C:\Elprotronic\Generic-FPA-DLL\Generic-CommandLine-Client.exe"
%CLIENT% -i 1 -m "configfileload <path-to-this-repo>\configs\imd111t-v105.cfg"
%CLIENT% -i 1 -m "readcodefile C:\Users\Sandhya\Downloads\IMD111T Demo test files\IMD111T Demo test files\Working_ClassB_disabled_I2Cdisable.ldf"
%CLIENT% -i 1 -m "autoprogram 1"
```

Expected: success. The chip programs and responds normally after.

Test 2 — deliberately brick the chip with a Not_Working file:
```cmd
%CLIENT% -i 1 -m "readcodefile C:\Users\Sandhya\Downloads\IMD111T Demo test files\IMD111T Demo test files\Not_Working_ClassB_enabled_I2Cdisable.ldf"
%CLIENT% -i 1 -m "autoprogram 1"
```

Expected: programming reports success, but the chip will be in Class-B-faulted state afterwards (no UART response to application-mode queries).

Test 3 — the key test. Recover the bricked chip via the FPA path:
```cmd
%CLIENT% -i 1 -m "readcodefile C:\Users\Sandhya\Downloads\IMD111T Demo test files\IMD111T Demo test files\Working_ClassB_disabled_I2Cdisable.ldf"
%CLIENT% -i 1 -m "autoprogram 1"
```

### Decision gate — this test result decides everything

- **Test 3 passes** → Option C is validated. The FPA path goes through v1.05's working catch-at-startup. Move on to Phase 4-5.
- **Test 3 fails the same way the v3.02 GUI does** → v1.05's API-DLL isn't actually being used. Loop back to Phase 1 step 3, fix the DLL search order, re-run.
- **Test 3 fails differently** → capture the server's verbose log, diagnose.

### Deliverable

Pass/fail result of Test 3, plus the server's verbose log for that test, saved under `logs/`.

---

## Phase 4 — wrap the CommandLine-Client in `flash-mce.py`

Goal: add `elprotronic-fpa` as a third backend in the `tam-imotion-flash` repo, alongside `iMOTIONconfig` and the pyserial stub. ~2-3 hours.

### New file: `scripts/elprotronic_fpa.py` (in tam-imotion-flash)

```python
"""elprotronic-fpa backend — drives the Elprotronic XStream-Iso adapter via
Elprotronic's Generic-FPA DLL command-line server.

Used for Class B-enabled parameter files where the v3.02 FlashPro-iMOTION
GUI has a regression that breaks catch-at-startup recovery. This backend
routes through the v1.05 FlashPro-iMOTION API-DLL (installed alongside
v3.02), which handles catch-at-startup correctly. See docs/07-elprotronic
-fpa-backend.md for setup and troubleshooting.
"""

from __future__ import annotations
import subprocess
import time
from pathlib import Path

FPA_ROOT = Path(r"C:\Elprotronic\Generic-FPA-DLL")
SERVER   = FPA_ROOT / "Generic-CommandLine-Server.exe"
CLIENT   = FPA_ROOT / "Generic-CommandLine-Client.exe"

def _client(cmd: str, fpa_index: int = 1) -> int:
    return subprocess.call([str(CLIENT), "-i", str(fpa_index), "-m", cmd])

def ensure_server_running(setup_ini: Path) -> None:
    # Probe with a trivial command. If the named pipe isn't open, spawn the
    # server detached so it outlives this script invocation.
    probe = subprocess.call(
        [str(CLIENT), "-m", "noop"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if probe == 0:
        return
    subprocess.Popen(
        [str(SERVER), "-setup", str(setup_ini), "-v", "1"],
        creationflags=subprocess.DETACHED_PROCESS,
    )
    time.sleep(1.0)

def autoprogram(setup_ini: Path, config: Path, ldf: Path, *, fpa_index: int = 1) -> int:
    ensure_server_running(setup_ini)
    steps = [
        f"set_fpa_index {fpa_index}",
        f"configfileload {config}",
        f"readcodefile {ldf}",
        "autoprogram 1",
    ]
    for cmd in steps:
        rc = _client(cmd, fpa_index)
        if rc != 0:
            return rc
    return 0
```

### Change to `scripts/flash-mce.py`

Add a `--backend` CLI flag (default `auto`, choices `imotionconfig` / `elprotronic-fpa` / `pyserial`). In `program_one`:

```python
if backend == "elprotronic-fpa":
    return elprotronic_fpa.autoprogram(
        setup_ini=Path("configs/elprotronic/setup.ini"),
        config=Path("configs/elprotronic/imd111t-v105.cfg"),
        ldf=path,
    )
```

Auto-detect rule (optional, defer if it makes the change too big in one shot):
- If `.ldf` has the Class B flag bit set in the static-params block → choose `elprotronic-fpa` if available.
- Otherwise → prefer `iMOTIONconfig`.

### Deliverable

A working backend that runs:
```cmd
python scripts\flash-mce.py --port COM7 --param path\to\Working.ldf --backend elprotronic-fpa
```
and produces the same result as the manual Phase 3 client commands.

---

## Phase 5 — documentation (commit to tam-imotion-flash after Phase 4 passes)

### New: `docs/07-elprotronic-fpa-backend.md` (in tam-imotion-flash)

Sections:
1. When to use this backend vs `iMOTIONconfig` (Class B work / v3.02 regression workaround / production automation).
2. Install: Generic-FPA DLL location, v1.05 install requirement, setup.ini location.
3. Daily usage: one `flash-mce.py` command line with `--backend elprotronic-fpa`.
4. Troubleshooting:
   - Server fails to load → check that `Generic-FPA.dll` is in the same dir as the server exe.
   - v3.02 API-DLL picked up instead of v1.05 → PATH ordering fix.
   - "Adapter not found" → check SN in `setup.ini` matches the physical label.
   - "configfileload failed" → the v1.05 config file format may not be accepted; copy a fresh one from the v1.05 GUI's File > Save As.

### Update: `docs/04-flashing-runbook.md`

Add a fourth bullet under "Reprogramming without a power cycle" pointing to the new doc. Add a fifth bullet under "Recovering a Class-B-bricked target" — preferred recovery path is now `--backend elprotronic-fpa` since it always uses catch-at-startup.

### Update: `README.md`

Backend comparison table:

| Backend | When to use |
|---|---|
| `iMOTIONconfig` | Default for non-Class-B flashing; uses Infineon's CLI |
| `elprotronic-fpa` | Class B parameter files + when Elprotronic GUI regression is in play |
| `pyserial` (stub) | Air-gapped fallback; not production-ready |

### Deliverable

One commit on `feat/imd111t-mce-only`:
```
feat(flash): add elprotronic-fpa backend for Class B work
```

---

## Risks and how to retire them early

| # | Risk | Retired by |
|---|------|------------|
| 1 | Generic-FPA DLL loads v3.02 API-DLL instead of v1.05 | Phase 1 step 3 |
| 2 | v1.05 config file format incompatible with Generic-FPA DLL's `configfileload` | Phase 3 Test 1 |
| 3 | The regression is in shared code below the API-DLL — Option C inherits it | Phase 3 Test 3 (binary outcome) |
| 4 | Generic-FPA DLL licensing requires per-machine activation | Discovered during install in Phase 1 |
| 5 | Named-pipe permissions issue between Python and the server (Windows UAC) | Discovered during Phase 4; fix is "run from elevated terminal" or relocate the server outside Program Files |

---

## What to do next, today

**Phase 1 only.** 15 minutes:

1. Download `Generic-win.zip`, unzip to `C:\Elprotronic\Generic-FPA-DLL\`.
2. Run the discovery command from Phase 1 step 2.
3. Save the verbose output to `phase1-discovery.log` (anywhere local; commit to this repo's `logs/` folder if you want to track it).
4. Decide based on which API-DLL path the server reports.

This single output decides whether the rest of the plan is shovel-ready or needs DLL-path adjustment.

---

## Source documents

- Generic-FPA DLL User's Guide: https://content.elprotronic.ca/docs/Generic-FPA-DLL-UserGuide.pdf
- Generic-FPA DLL download: https://content.elprotronic.ca/downloads/Generic-win.zip
- Elprotronic FlashPro-iMOTION product page: https://www.elprotronic.com/pages/imotion
- AN2018-33 iMOTION Device Programming: https://www.infineon.com/assets/row/public/documents/60/42/infineon-an2018-33-imotion-2.0-device-programming-applicationnotes-en.pdf
