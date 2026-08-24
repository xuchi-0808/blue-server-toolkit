#!/bin/bash
# blue_server_toolkit - PID to Container Lookup
# Version: 1.0
# Given a host-side PID (e.g. from npu-smi info), find which Docker container
# it belongs to by parsing /proc/<pid>/cgroup on the remote server.
# Supports cgroup v1 (/docker/<id>) and v2 (docker-<id>.scope) layouts.
#
# Usage: bash who.sh <host> <user> <pid>

HOST=$1
USER=$2
PID=$3

if [ $# -lt 3 ]; then
  echo "Usage: bash who.sh <host> <user> <pid>"
  exit 1
fi

ssh "$USER@$HOST" '
  cg=/proc/'"$PID"'/cgroup
  if [ ! -r "$cg" ]; then
    echo "PID '"$PID"' not found on remote host (or no permission)"
    exit 1
  fi
  line=$(grep -m1 -E "docker[-/]" "$cg")
  cid=$(printf "%s\n" "$line" | sed -n \
    -e "s/.*docker-\([0-9a-f]\{64\}\)\.scope.*/\1/p" \
    -e "s|.*/docker/\([0-9a-f]\{64\}\).*|\1|p")
  if [ -z "$cid" ]; then
    echo "PID '"$PID"' is not running inside a docker container"
    printf "cgroup: %s\n" "$line"
    exit 2
  fi
  echo "PID '"$PID"' -> container $cid"
  docker ps -a --filter "id=$cid" --format "{{.ID}}  {{.Image}}  {{.Names}}  {{.Status}}"
'
