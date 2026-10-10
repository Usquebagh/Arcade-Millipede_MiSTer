#!/bin/bash
# Build the MiSTer core with Quartus Lite 17.0.2 in Docker.
# Output: output_files/Arcade-Millipede.rbf (copied to releases/Arcade-Millipede_<date>.rbf)
set -e
cd "$(dirname "$0")"
IMAGE=theypsilon/quartus-lite-c5:17.0.2
start=$(date +%s)
docker run --rm -v "$PWD":/project -w /project -u "$(id -u):$(id -g)" "$IMAGE" \
  quartus_sh --flow compile Arcade-Millipede.qpf > build.log 2>&1 || {
    grep -E "^(Error|Critical Warning)" build.log | head -30
    tail -5 build.log
    exit 1
  }
echo "build took $(( $(date +%s) - start )) s"
grep -E "Logic utilization|Total block memory bits|Total registers|RAM Blocks" output_files/Arcade-Millipede.fit.summary || true
grep -E "Worst-case setup slack|Critical Warning.*[Tt]iming" build.log | head -5 || true
mkdir -p releases
cp output_files/Arcade-Millipede.rbf "releases/Arcade-Millipede_$(date +%Y%m%d).rbf"
ls -l releases/
