#!/usr/bin/env bash
# link-dev.sh — 开发模式安装脚本：为四个工具的每个 skill 建软链
# （链接直接指向仓库内 skills/<name>）。
#
# 用法：
#   ./link-dev.sh             安装/修复全部 skill 链接（重复执行结果不变）
#   ./link-dev.sh --check     只检查状态，不改任何东西；检查失败时退出码 1
#   ./link-dev.sh --unlink    删除所有指向本仓库的链接（指向其他仓库的不动）
#   ./link-dev.sh --prune-old 清理旧的单 skill 布局遗留链接
#                             （解析到仓库根目录本身的那批链接）
#
# 规则：
#   - 目标位置是其他仓库的实体目录、或指向别处的链接 → 报冲突并拒绝改动
#     （绝不覆盖无关 skill）
#   - ~/.codex/skills/.system/ 永不触碰
#   - 开发软链与插件安装互斥：装插件前先 --unlink（软链注册不带前缀的
#     skill 名，插件注册带前缀的 plugin:skill 名，两者会同时加载两份）
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
TARGETS=(
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "$HOME/.config/opencode/skills"
  "$HOME/.zcode/skills"
)
CODEX_SYSTEM=".system"

MODE="install"
case "${1:-}" in
  --check) MODE="check" ;;
  --unlink) MODE="unlink" ;;
  --prune-old) MODE="prune-old" ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

rp() { # 解析软链的最终目标（readlink -f 不可用时用 python 兜底）
  readlink -f "$1" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || true
}

# 收集 skill 清单（目录内必须含 SKILL.md）
SKILLS=()
for d in "$SKILLS_DIR"/*/; do
  name="$(basename "$d")"
  [[ -f "$d/SKILL.md" ]] || { echo "ERROR: skills/$name 缺 SKILL.md，跳过" >&2; continue; }
  SKILLS+=("$name")
done
[[ ${#SKILLS[@]} -gt 0 ]] || { echo "ERROR: $SKILLS_DIR 下没有有效 skill" >&2; exit 1; }

fail=0
declare -a summary=()

for base in "${TARGETS[@]}"; do
  tool="$(basename "$(dirname "$base")")/$(basename "$base")"
  for name in "${SKILLS[@]}"; do
    link="$base/$name"
    want="$SKILLS_DIR/$name"

    # codex 系统目录保护（理论上不会命中，防御性保留）
    [[ "$link" == "$HOME/.codex/skills/$CODEX_SYSTEM"/* ]] && continue

    if [[ "$MODE" == "unlink" ]]; then
      if [[ -L "$link" ]]; then
        resolved="$(rp "$link")" || resolved=""
        direct="$(readlink "$link")"
        if [[ "$resolved" == "$REPO_ROOT"* || "$direct" == *"blue-server-toolkit"* ]]; then
          rm "$link" && summary+=("unlinked  $tool/$name")
        fi
      fi
      continue
    fi

    if [[ "$MODE" == "prune-old" ]]; then
      # 旧布局：链接解析到仓库根目录本身（而不是 skills/<name>）
      if [[ -L "$link" ]]; then
        resolved="$(rp "$link")" || resolved=""
        if [[ "$resolved" == "$REPO_ROOT" ]]; then
          rm "$link" && summary+=("pruned-old $tool/$name -> repo root")
        fi
      fi
      continue
    fi

    if [[ -L "$link" ]]; then
      resolved="$(rp "$link")" || resolved=""
      if [[ "$resolved" == "$want" ]]; then
        [[ "$MODE" == "check" ]] && summary+=("ok        $tool/$name")
      elif [[ "$resolved" == "$REPO_ROOT"* ]]; then
        # 指向本仓库但目标不对（含旧的单 skill 链接、嵌套软链）→ 原子修复
        if [[ "$MODE" == "check" ]]; then
          summary+=("stale     $tool/$name -> $resolved"); fail=1
        else
          ln -sfn "$want" "$link" && summary+=("repaired  $tool/$name (was $resolved)")
        fi
      else
        summary+=("CONFLICT  $tool/$name -> $resolved（非本仓库，拒绝改动）"); fail=1
      fi
    elif [[ -e "$link" ]]; then
      summary+=("CONFLICT  $tool/$name 是实体目录/文件，拒绝改动"); fail=1
    else
      if [[ "$MODE" == "check" ]]; then
        summary+=("missing   $tool/$name"); fail=1
      else
        mkdir -p "$base"
        ln -s "$want" "$link" && summary+=("created   $tool/$name")
      fi
    fi
  done
done

printf '%s\n' "${summary[@]}" | sort
echo "---"
if [[ "$MODE" == "check" ]]; then
  [[ $fail -eq 0 ]] && echo "OK: ${#SKILLS[@]} 个 skill 在 ${#TARGETS[@]} 个工具下的链接全部就绪" \
                    || { echo "CHECK FAILED（见上方 missing/stale/CONFLICT）"; exit 1; }
else
  echo "完成。验证：在四个工具里各开一个新会话，确认 ${#SKILLS[@]} 个 blue-* skill 出现（hub 应为 3.x 版内容）。"
fi
