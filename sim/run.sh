#!/bin/bash
# Build and run the Verilator simulation.
#   sim/run.sh [frames] [dump_every]
# ROMs are read from $MP_ROMS (default ~/jt/millipede/roms); output goes to sim/out/.
set -e
cd "$(dirname "$0")"
ROMS=${MP_ROMS:-$HOME/jt/millipede/roms}
mkdir -p out/roms
python3 mkroms.py "$ROMS" out/roms > /dev/null


VSRC="$(ls ../rtl/pokey/*.v) ../rtl/dpram.v ../rtl/millipede_dac.v ../rtl/millipede_audio.v
  ../rtl/millipede.v ../rtl/cpu6502/cpu.v ../rtl/cpu6502/ALU.v"

if [ ! -x obj_dir/Vmillipede ] || [ -n "$(find ../rtl sim_main.cpp run.sh -newer obj_dir/Vmillipede -name '*.*' | head -1)" ]; then
verilator --cc --exe --build -j "$(nproc)" -O3 --x-assign fast --x-initial fast \
  -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY \
  -Wno-PINMISSING -Wno-MULTIDRIVEN -Wno-COMBDLY -Wno-IMPLICIT -Wno-TIMESCALEMOD \
  --public-flat-rw --top-module millipede -DSIMULATION \
  -Mdir obj_dir $VSRC sim_main.cpp > out/build.log 2>&1 || { grep -E "%Error" out/build.log | head -30; tail -5 out/build.log; exit 1; }
fi

cd out
rm -f frame_*.ppm frame_*.png
time ../obj_dir/Vmillipede "${1:-60}" "${2:-10}"
python3 - <<'EOF'
import glob
from PIL import Image
for f in sorted(glob.glob("frame_*.ppm")):
    Image.open(f).save(f[:-4] + ".png")
EOF
ls frame_*.png 2>/dev/null | tail -3
