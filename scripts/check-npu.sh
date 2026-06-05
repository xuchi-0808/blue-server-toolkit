#!/bin/bash
# blue_server_handler - NPU Status Check
# Version: 0.9
# Runs npu-smi info on the target server via SSH (optionally inside a container).
#
# Usage: bash check-npu.sh <host> <user> [container]

HOST=$1
USER=$2
CONTAINER=$3

if [ $# -lt 2 ]; then
  echo "Usage: bash check-npu.sh <host> <user> [container]"
  exit 1
fi

if [ -n "$CONTAINER" ]; then
  ssh "$USER@$HOST" "docker exec $CONTAINER npu-smi info" 2>&1
else
  ssh "$USER@$HOST" "npu-smi info" 2>&1
fi
