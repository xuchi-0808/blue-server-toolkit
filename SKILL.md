---
name: blue_server_handler
description: >-
  Use when operating remote development servers (blue-zone servers). Provides
  server connection checks, code sync, UT execution, model downloads, log
  viewing, container management, and file sync capabilities.
metadata:
  version: 0.9
---

# Blue Server Handler

## Overview

A skill for operating remote development servers. It covers 80% of daily
operations through a combination of prompt-guided patterns and small helper
scripts. The skill is designed to work with any server and any AI tool -- it
is not bound to specific machines or agents.

**Core principles:**

1. **Not bound to specific machines** -- all server info comes from
   `~/.blue_server_handler/config.json`
2. **Prompt-first, script-assisted** -- AI handles most operations by
   composing commands on the fly; scripts cover high-frequency / complex tasks
3. **Self-installing** -- this SKILL.md contains everything needed; AI
   extracts scripts and sets up config on first activation
4. **Configuration is alive** -- AI reads, updates, and migrates config
   proactively; users just tell AI what changed
5. **Ask when unsure** -- when config is ambiguous, multiple servers match,
   or a value looks suspicious, always confirm with the user before acting

## First Activation

When this skill is activated for the first time, follow these steps:

### 1. Install Scripts

```bash
VERSION="0.9"
SCRIPTS_DIR="$HOME/.blue_server_handler/scripts_${VERSION}"

# Check if already installed
if [ ! -d "$SCRIPTS_DIR" ]; then
  # Clean up old versions
  rm -rf "$HOME/.blue_server_handler"/scripts_*

  # Create directory
  mkdir -p "$SCRIPTS_DIR"

  # Extract scripts from the "## Scripts" section below and write them here
  # (AI will read the code blocks and write them to files)
  echo "✅ Scripts installed to $SCRIPTS_DIR"
fi
```

### 2. Check Configuration

Check if `~/.blue_server_handler/config.json` exists. If not, guide the user
to provide basic server info (host, user, container). Write the config file
with a `version` field matching this SKILL.md's version.

**Config fields to ask about on first setup (only required ones):**

| Field | Ask | Required |
|-------|-----|----------|
| `servers[].host` | "What's the server IP or domain?" | Yes |
| `servers[].user` | "What's your SSH username?" | Yes |
| `servers[].container` | "What's the Docker container name?" | Yes |
| `servers[].alias` | "What alias should I use for this server?" (default: s1) | No |
| `servers[].port` | (default: 22) | No |
| `servers[].desc` | (optional description) | No |
| `default_server` | "Which server should I use by default?" | No |

**Optional sections** (only show when user asks):
- `workspaces` -- directory conventions on the server
- `restrictions` -- safety rules (forbidden / confirm-required commands)

### 3. Announce Capability

After setup, tell the user:

> "I've configured blue_server_handler. You can now ask me to check the server,
> run tests, sync code, or any other server task. If you ever need to change
> the configuration (new server, changed IP, etc.), just let me know and I'll
> update it for you."

### 4. Version Update Check

Compare `config.json.version` with this SKILL.md's version:

- **Same** -- continue normally
- **Different** -- perform update:
  1. Delete all `$HOME/.blue_server_handler/scripts_*` directories
  2. Extract new scripts from this SKILL.md
  3. Migrate config: keep user values, add any new fields, update version
  4. Notify user of the update

## Configuration Management

The full config schema is available in `config.example.json` (shipped with this
repo). Users can reference it to see all available fields.

### Reading Config

Read `~/.blue_server_handler/config.json` at the start of each activation.
Inject the values as your working context.

```json
{
  "version": "0.9",
  "servers": [
    {
      "alias": "s1",
      "host": "192.168.1.100",
      "user": "developer",
      "port": 22,
      "container": "dev_container",
      "desc": "Main dev server"
    }
  ],
  "default_server": "s1",
  "workspaces": {
    "task_root": "/home/developer/Tasks",
    "weights_root": "/home/developer/weights",
    "code_root": "/home/developer/Code"
  },
  "restrictions": {
    "forbidden_commands": [
      "sudo rm -rf /",
      "reboot",
      "shutdown",
      "init 0",
      "init 6"
    ],
    "confirm_required": [
      "rm -rf",
      "docker rm",
      "docker rmi",
      "kill -9"
    ]
  }
}
```

### Updating Config

Update config when:
- User mentions a change ("I changed the server IP", "add a new server")
- You detect inconsistency between what the user says and current config

When uncertain (ambiguous value, multiple matches), ask the user before
changing anything.

### Restrictions

If `restrictions.forbidden_commands` is set: never execute matching commands.
Refuse and explain why.

If `restrictions.confirm_required` is set: execute only after explicit user
confirmation.

If `restrictions` is absent: use common sense safety (no destructive
operations without confirmation). Do not proactively suggest adding
restrictions unless the user asks about safety features.

## Core Skills

### 1. Connection Check

Check SSH reachability, Docker container status, and NPU device health.

| Operation | Command | Description |
|-----------|---------|-------------|
| SSH ping | `ssh -o ConnectTimeout=5 {user}@{host} "echo OK"` | Quick reachability check |
| Container status | `ssh {user}@{host} "docker ps \| grep {container}"` | Check if container is running |
| NPU status | `bash $HOME/.blue_server_handler/scripts_{version}/check-npu.sh {host} {user} {container}` | NPU device status |
| Disk space | `ssh {user}@{host} "df -h \| grep {user}"` | User directory disk usage |

**Flow:**
1. User asks to check server → determine target from config or ask
2. Run: SSH ping → container check → NPU check
3. Summarize results, flag anomalies
4. Multiple servers and no target specified → ask which one

**Common issues:**
- SSH timeout → suggest checking VPN / network
- Container not running → suggest `docker start {container}`
- NPU error → suggest checking `npu-smi` output in detail

### 2. Code Operations

Git operations on the remote server: clone, pull, branch switch, status.

| Operation | Command | Description |
|-----------|---------|-------------|
| Clone | `ssh {user}@{host} "git clone {repo_url} {target_dir}"` | First-time clone |
| Force pull | `ssh {user}@{host} "cd {repo_dir} && git fetch origin && git reset --hard origin/{branch}"` | Sync with remote |
| Switch branch | `ssh {user}@{host} "cd {repo_dir} && git checkout {branch}"` | Change branch |
| Check status | `ssh {user}@{host} "cd {repo_dir} && git status"` | Working tree status |
| Create symlink | `ssh {user}@{host} "ln -sf {src} {dst}"` | Directory symlink |

**Flow:**
1. User states intent → confirm repo path and branch
2. Execute git operation
3. Report summary: branch, latest commit, uncommitted changes

**Common issues:**
- Uncommitted changes blocking reset → stash first
- Path not found → ask user to confirm
- Permission denied → check SSH key / repo access

### 3. UT Execution

Run unit tests inside the server's Docker container.

| Operation | Command | Description |
|-----------|---------|-------------|
| Single file | `ssh {user}@{host} "docker exec {container} bash -c 'cd {repo_dir} && python3 -m pytest {test_file} -v'"` | One test file |
| Batch | `ssh {user}@{host} "docker exec {container} bash -c 'cd {repo_dir} && python3 -m pytest {file1} {file2} -v'"` | Multiple files |
| With coverage | `ssh {user}@{host} "docker exec {container} bash -c 'cd {repo_dir} && coverage run -m pytest {test_file} -v && coverage report -m'"` | Coverage report |
| By directory | `ssh {user}@{host} "docker exec {container} bash -c 'cd {repo_dir} && python3 -m pytest tests/{subdir}/ -v'"` | Directory |

**Flow:**
1. User asks to run tests → confirm files / directory / coverage option
2. Construct and execute command via docker exec
3. Report: passed / failed / skip counts
4. On failure → extract error details, suggest next steps

**Common issues:**
- Missing dependency → suggest pip install inside container
- Wrong python path → try `python` vs `python3`
- Container not running → start container first

### 4. Model Download

Download model weights via ModelScope CLI on the server.

| Operation | Command | Description |
|-----------|---------|-------------|
| Download | `ssh {user}@{host} "docker exec {container} bash -c 'cd {weights_root} && nohup modelscope download {model_id} >> download.log 2>&1 &'"` | Background download |
| Check progress | `ssh {user}@{host} "tail -f {weights_root}/download.log"` | Live log tail |
| Check disk | `ssh {user}@{host} "df -h {weights_root}"` | Space check before download |
| Verify | `ssh {user}@{host} "du -sh {weights_root}/{model_name}"` | Confirm download complete |

**Fault handling chain** (try in order, escalate automatically):

```
① modelscope CLI not found → pip install modelscope
② pip install fails → try mirror source (e.g., Tsinghua), check proxy
③ all automated attempts fail → report to user: what was tried, where it
   failed, suggested action
```

**Flow:**
1. User requests model download → confirm model_id, suggest background run
2. Check disk space before starting
3. Construct nohup background command, tell user how to check progress
4. Optionally check download status periodically

**Common issues:**
- Insufficient disk space → report space, suggest cleanup
- modelscope install failure → follow fault handling chain
- Download interrupted → check log, suggest retry

### 5. Log Viewing

View container logs and task output files with grep filtering.

| Operation | Command | Description |
|-----------|---------|-------------|
| Container logs | `ssh {user}@{host} "docker logs {container} {--tail N}"` | Container stdout/stderr |
| Tail file | `ssh {user}@{host} "tail -f {log_file}"` | Live file follow |
| Search keyword | `ssh {user}@{host} "grep -n {keyword} {log_file}"` | Find matching lines |
| Read file | `ssh {user}@{host} "cat {log_file}"` | Full file content |
| Last N lines | `ssh {user}@{host} "tail -n 100 {log_file}"` | Tail only |

**Flow:**
1. User asks about logs → clarify: container logs or file logs?
2. Execute and retrieve content
3. If output is large, filter with grep or suggest keyword
4. Summarize anomalies / errors

**Common issues:**
- Log file path unknown → ask user or search common locations
- Log too large → limit lines, suggest keyword filter
- Empty container logs → check if container has output

### 6. Container Management

Start, stop, restart, and enter Docker containers.

| Operation | Command | Description |
|-----------|---------|-------------|
| Enter container | `ssh {user}@{host} "docker exec -it {container} bash"` | Interactive shell |
| Start | `ssh {user}@{host} "docker start {container}"` | Start stopped container |
| Restart | `ssh {user}@{host} "docker restart {container}"` | Restart running container |
| Check status | `ssh {user}@{host} "docker ps -a \| grep {container}"` | All containers status |
| Execute command | `ssh {user}@{host} "docker exec {container} bash -c '{command}'"` | Run command inside |

**Flow:**
1. User says "enter the container" or "restart" → confirm target
2. Execute
3. Verify container state afterward

**Common issues:**
- Container not found → check container name in config
- Create fails → check image / resources / port conflicts
- Restart needs time → suggest waiting a few seconds before verifying

### 7. File Sync

Transfer files between local and remote server.

| Operation | Command | Description |
|-----------|---------|-------------|
| Upload file | `scp {local_path} {user}@{host}:{remote_path}` | Local → Remote |
| Download file | `scp {user}@{host}:{remote_path} {local_path}` | Remote → Local |
| Upload dir | `scp -r {local_dir} {user}@{host}:{remote_dir}` | Recursive upload |
| Download dir | `scp -r {user}@{host}:{remote_dir} {local_dir}` | Recursive download |
| Incremental sync | `rsync -avz {local_dir} {user}@{host}:{remote_dir}` | Rsync |

**Flow:**
1. User says "transfer a file" → confirm direction, paths
2. Execute transfer
3. Verify file exists on destination

**Common issues:**
- Large file interrupted → suggest rsync for resume
- Target directory missing → create it first
- Permission denied → check target path permissions

## Fault Handling

When any operation fails, follow this chain automatically:

```
① Auto-repair → ② Alternative approach → ③ Report to user
```

- **Auto-repair**: identify common failures and fix (install dependency,
  retry on timeout, check config)
- **Alternative approach**: if the primary method fails, try alternatives
  (different python path, mirror source, rsync instead of scp)
- **Report to user**: when all automated attempts are exhausted, clearly
  report: what was tried, what failed, and what the user can do next

## Scripts

These scripts are embedded in this SKILL.md. On first activation (or version
update), the AI extracts them to `$HOME/.blue_server_handler/scripts_{version}/`.

### check-npu.sh

```bash
#!/bin/bash
# blue_server_handler - NPU Status Check
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
```

### init-config.sh

```bash
#!/bin/bash
# blue_server_handler - Initialize Configuration
# Usage: bash init-config.sh

CONFIG_DIR="$HOME/.blue_server_handler"
CONFIG_FILE="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR/scripts"

if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "0.9",
  "servers": [
    {
      "alias": "s1",
      "host": "__your_host__",
      "user": "__your_user__",
      "port": 22,
      "container": "__your_container__",
      "desc": "Main dev server"
    }
  ],
  "default_server": "s1"
}
EOF
  echo "Template config created at $CONFIG_FILE. Fill in your server info, or ask AI to help."
else
  echo "Config already exists at $CONFIG_FILE"
fi
```

## Extending

To add a new script to this skill:

1. Add the script to the `scripts/` directory in the repository
2. Embed it as a code block in the "## Scripts" section above (must be identical)
3. Bump the version in frontmatter `metadata.version`

**Important**: Before release, verify that `scripts/` files and SKILL.md code blocks are identical. The AI extracts scripts from SKILL.md; `scripts/` is the development source of truth for verification.
