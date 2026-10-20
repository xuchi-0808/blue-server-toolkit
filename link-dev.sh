#!/usr/bin/env bash
# link-dev.sh — 开发态安装器：为四工具建逐 skill 软链（直链仓内 skills/<name>）。
#
# 用法：
#   ./link-dev.sh             安装/修复全部 skill 链接（幂等）
#   ./link-dev.sh --check     只检查状态，不改任何东西；异常退出码 1
#   ./link-dev.sh --unlink    拆除所有指向本仓的链接（他者内容不动）
#   ./link-dev.sh --prune-old 清理旧单 skill 形态遗留链接（指向仓根本身的链）
#
# 规则：
#   - 目标是他者实体目录/指向别处的链接 → 报冲突并拒动（绝不覆盖无关 skill）
#   - ~/.codex/skills/.system/ 永不触碰
#   - 开发链与插件安装互斥：装插件前先 --unlink（裸名与 plugin:skill 限定名
#     是不同加载键，同机会双载）
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

rp() { # realpath with fallback
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
      # 旧形态：链接解析到仓根本身（而非 skills/<name>）
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
        # 指向本仓但目标不对（含旧单链形态、二级链）→ 原子修复
        if [[ "$MODE" == "check" ]]; then
          summary+=("stale     $tool/$name -> $resolved"); fail=1
        else
          ln -sfn "$want" "$link" && summary+=("repaired  $tool/$name (was $resolved)")
        fi
      else
        summary+=("CONFLICT  $tool/$name -> $resolved（非本仓，拒动）"); fail=1
      fi
    elif [[ -e "$link" ]]; then
      summary+=("CONFLICT  $tool/$name 是实体目录/文件，拒动"); fail=1
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
  [[ $fail -eq 0 ]] && echo "OK: ${#SKILLS[@]} 个 skill × ${#TARGETS[@]} 工具链接全部就绪" \
                    || { echo "CHECK FAILED（见上方 missing/stale/CONFLICT）"; exit 1; }
else
  echo "完成。验证：四工具各开新会话，确认 ${#SKILLS[@]} 个 blue-* skill 出现（hub 内容为 3.x）。"
fi
