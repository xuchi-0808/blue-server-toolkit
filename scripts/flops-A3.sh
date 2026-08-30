#!/bin/bash
# blue_server_toolkit - A3 Compute Power (TFLOPS@FP16) Measurement
# Version: 1.0
# Sources Ascend env on the host, runs ascend-dmi floating-point test on
# chips 0-7, then summarizes TFLOPS@FP16 and classifies the machine:
# ~560-580 => "560T" SKU, ~750+ => "752T" SKU.
#
# NOTE: this is a REAL compute benchmark (~2s, ~300W per chip). Do not
# run while other jobs occupy the NPUs.
#
# Usage: bash flops-A3.sh <host> <user>

HOST=$1
USER=$2

if [ $# -lt 2 ]; then
  echo "Usage: bash flops-A3.sh <host> <user>"
  exit 1
fi

ssh "$USER@$HOST" 'bash -s' <<'REMOTE'
  source /usr/local/Ascend/toolbox/set_env.sh 2>/dev/null
  source /usr/local/Ascend/ascend-toolkit/set_env.sh 2>/dev/null
  if ! command -v ascend-dmi >/dev/null 2>&1; then
    echo "ERROR: ascend-dmi not found — host missing Ascend toolbox package."
    echo "Fix (root): get Ascend-mindx-toolbox_<ver>_linux-aarch64.run from hiascend"
    echo "CANN download page, then ./Ascend-mindx-toolbox_<ver>_linux-aarch64.run --install"
    echo "(toolbox version must match the installed NPU driver)"
    exit 1
  fi
  LOG=/tmp/a3-flops.log
  for i in {0..7}; do
    ascend-dmi -f -d $i -q
  done > "$LOG" 2>&1
  # Data rows: Device col is a chip pair like "0/1"; col 4 = TFLOPS@FP16
  if ! awk '
    $1 ~ /^[0-9]+\/[0-9]+$/ && NF >= 5 {
      n++; s+=$4
      if (n==1 || $4<mn) mn=$4
      if ($4>mx) mx=$4
      printf "  %-6s %s TFLOPS@FP16\n", $1, $4
    }
    END {
      if (n==0) exit 1
      printf "measured=%d  min=%.1f  avg=%.1f  max=%.1f\n", n, mn, s/n, mx
      printf "=> A3 %s machine (avg TFLOPS@FP16 ~ %d)\n", (s/n >= 650 ? "752T" : "560T"), s/n
    }' "$LOG"; then
    echo "WARN: no TFLOPS rows parsed, raw ascend-dmi output:"
    cat "$LOG"
    exit 2
  fi
  echo "raw tables kept on host: $LOG"
REMOTE
