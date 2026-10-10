# Millipede (Arcade, 1982) for MiSTer FPGA

An FPGA implementation of Atari's **Millipede** for the
[MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki) platform, built from Atari's
schematic package SP-217 (game PCB 038874).

> **Early build.** Feedback and bug reports are welcome via
> [Issues](https://github.com/Usquebagh/Arcade-Millipede_MiSTer/issues).

## Original Hardware

| Subsystem | Original Hardware | FPGA Implementation |
|---|---|---|
| **CPU** | MOS 6502 @ 1.512 MHz (stretched on playfield RAM accesses) | Arlet Ottens' verilog-6502 |
| **Sound** | 2 x Atari POKEY @ 1.512 MHz, current-to-voltage output stage | POKEY by Mark Watson; output stage modelled from the schematic |
| **Video** | 32 x 30 playfield, 16 motion objects per line, 32-entry colour RAM | `rtl/millipede.v`, from the schematics |
| **Display** | 256 x 240, vertical (ROT270), 59.88 Hz | Rotated with the MiSTer framebuffer |
| **Controls** | Trak-Ball and one button (cocktail: one per player) | Mouse as Trak-Ball, or joystick (the game reads a joystick port) |
| **High scores** | ER2055 EAROM | Saved to the SD card |

Notes on the hardware are in [docs/hardware.md](docs/hardware.md).

## Controls

| Input | Function |
|---|---|
| **Mouse** | Trak-Ball (speed in the OSD) |
| **D-Pad** | Joystick |
| **A** / left mouse button | Fire |
| **Start** | Start 1 player |
| **Select** | Coin |

## OSD options

- **Cabinet**: Upright or Cocktail. In cocktail mode the picture turns for player 2; the core
  rotates the other way so it stays upright on one screen.
- **Advanced → Colours**: *Board* uses levels worked out from the colour output resistors;
  *MAME* uses MAME's weights (MAME's greens are darker).
- **Advanced → Audio Output**: *Board* models the POKEY output stage (non-linear POKEY volume
  steps, the C63/R153 low-pass and the coupling high-pass); *MAME* is MAME's linear mix.
- **DIP switches** from the MRA, as in MAME.

## ROMs

ROMs are not included. Use the MRA files in `releases/` with the MAME `milliped.zip` set
(`millipdd` for the Dux hack).

## Credits

- Based on the MiSTer Centipede core (lisper's Centipede FPGA implementation, MiSTer port by
  Alan Steremberg), from which the POKEY, PLL, high-score, pause and trackball modules come.
- POKEY: Mark Watson. 6502: Arlet Ottens. High-score and pause modules: Jim Gregory.
- MAME (`atari/centiped.cpp`) was used as a reference for comparison.
