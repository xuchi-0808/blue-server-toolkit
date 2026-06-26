#!/bin/bash
# blue_server_toolkit - Initialize Configuration
# Version: 1.0
# Creates ~/.blue_server_toolkit/ directory structure, config, scripts, and docs.
#
# Usage: bash init-config.sh

CONFIG_DIR="$HOME/.blue_server_toolkit"
CONFIG_FILE="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR/scripts" "$CONFIG_DIR/docs"

if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "1.0",
  "servers": [
    {
      "alias": "s1",
      "host": "__your_host__",
      "user": "__your_user__",
      "port": 22,
      "container": null,
      "desc": "主开发服务器"
    }
  ],
  "default_server": "s1"
}
EOF
  echo "✅ Template config created at $CONFIG_FILE"
  echo "   Fill in your server info, or ask AI to help configure it."
else
  echo "ℹ️  Config already exists at $CONFIG_FILE"
fi

# Copy scripts if source directory is available
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SCRIPT_DIR" ] && [ "$SCRIPT_DIR" != "$CONFIG_DIR/scripts" ]; then
  cp "$SCRIPT_DIR"/*.sh "$CONFIG_DIR/scripts/" 2>/dev/null && echo "✅ Scripts installed to $CONFIG_DIR/scripts/"
fi

# Copy docs if source directory is available
if [ -d "$SCRIPT_DIR/../docs" ]; then
  cp "$SCRIPT_DIR/../docs"/*.md "$CONFIG_DIR/docs/" 2>/dev/null && echo "✅ Docs installed to $CONFIG_DIR/docs/"
fi
