# SV08MAX
# Sovol SV08 Max - Custom Configuration & Backup

This repository is a customized fork of the official [Sovol3d/SV08MAX](https://github.com/Sovol3d/SV08MAX) repository, specifically maintained for a tuned **Sovol SV08 Max** CoreXY 3D printer.

---

## 📌 Repository Purpose & Branching Strategy

- **Upstream (`upstream`)**: [https://github.com/Sovol3d/SV08MAX.git](https://github.com/Sovol3d/SV08MAX.git) (Sovol's stock factory release).
- **Working Branch (`jb_custom`)**: Contains custom Klipper configurations, Eddy current probe tunings, macro enhancements, and motion optimizations.
- **`home/sovol-live/`**: A curated 1:1 backup and mirror of the live filesystem pulled directly from `/home/sovol/` on the physical printer.

---

## 📂 Repository Structure

```
SV08MAX/
├── home/
│   ├── sovol-live/                 # Clean 1:1 mirror of the physical printer's /home/sovol
│   │   ├── printer_data/config/    # Live configuration files running on the printer
│   │   ├── printer_data/database/  # Moonraker database (moonraker-sql.db)
│   │   ├── klipper/                # Klipper firmware source installed on the printer
│   │   ├── moonraker/              # Moonraker API server installed on the printer
│   │   ├── mainsail/               # Mainsail web interface build
│   │   ├── KlipperScreen/          # KlipperScreen UI
│   │   ├── zhongchuang/            # Sovol Makerbase touchscreen app & Debian package tree
│   │   └── *.sh, ttyS3.py          # Sovol system scripts (PLR, IP display, recovery)
│   │
│   └── sovol/                      # Stock / tracked repository configuration
│       ├── printer_data/config/    # Primary working directory for tracked printer configs
│       ├── patch/config/           # Sovol factory default configs (used by patch.sh)
│       └── zhongchuang/            # Screen app C++ source code
│
├── Motherboard/                    # Hardware schematics and pinout diagrams
├── PDF/                            # Manuals and documentation
└── STEP/                           # Official 3D CAD STEP models for the printer
```

---

## 🖨️ Printer Hardware & Kinematics Reference

When generating or editing configuration files and macros, keep the following hardware specifications in mind:

- **Kinematics**: CoreXY
- **Build Volume**: 500 mm × 500 mm × 500 mm (Quad Gantry Leveling / 4 Z steppers)
- **Toolhead & Probe**: BTT Eddy Current probe (`probe_eddy_current eddy`) configured for rapid scanning and contact/non-contact Z-offset calibration.
- **Controller Setup**:
  - Main MCU: Primary motherboard controlling XY motion, quad-Z steppers, heated bed, and fans.
  - Toolhead / Extra MCU: Connected via USB/CAN bus controlling extruder, hotend, accelerometer, and eddy probe.
- **Klipper Version Notes**:
  - Uses modern Klipper kinematic settings (e.g., `minimum_cruise_ratio: 0.25` instead of deprecated `max_accel_to_decel`).
  - Bed meshes are sampled at high resolution across the 500×500 mm bed using Eddy rapid scan.

---

## 🔍 Context for AI Assistants & LLMs

When modifying, analyzing, or troubleshooting files in this repository:

1. **Active Configuration Edits**:
   - Edit configuration files under [`home/sovol/printer_data/config/`](file:///c:/Users/stupi/Project/Other/SV08MAX/home/sovol/printer_data/config) (e.g., `printer.cfg`, `Macro.cfg`, `moonraker.conf`, `crowsnest.conf`).
   - Compare against [`home/sovol-live/printer_data/config/`](file:///c:/Users/stupi/Project/Other/SV08MAX/home/sovol-live/printer_data/config) when verifying what is currently deployed on the physical printer.
2. **Factory Fallbacks**:
   - Default stock configs reside in [`home/sovol/patch/config/`](file:///c:/Users/stupi/Project/Other/SV08MAX/home/sovol/patch/config). Do not modify these unless altering the factory reset baseline.
3. **Filesystem Hygiene**:
   - Never commit Python virtual environments (`*-env/`), rolling logs (`printer_data/logs/`), sliced files (`printer_data/gcodes/`), or IDE/agent folders (`.vscode-server`, `.gemini`).
   - Keep `home/sovol-live/` free of transient runtime logs and user gcodes so it remains a lightweight, reliable backup.