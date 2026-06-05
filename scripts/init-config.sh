#!/bin/bash
# blue_server_handler - Initialize Configuration
# Version: 0.9
# Creates ~/.blue_server_handler/ directory structure and a template config.
#
# Usage: bash init-config.sh

CONFIG_DIR="$HOME/.blue_server_handler"
CONFIG_FILE="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR"

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
