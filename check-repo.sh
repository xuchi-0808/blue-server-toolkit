#!/usr/bin/env bash
# check-repo.sh — 3.x 合并前检查：目录结构/清单/frontmatter/契约块/
# 版本号三处一致/行数上限/仓库整洁。
# 用法：./check-repo.sh [--strict]   退出码 0=通过，1=失败；
# warning 在 --strict 下也计为失败。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
STRICT="${1:-}"
hard=0; warn=
fail() { echo "FAIL  $*"; hard=1; }
warnn() { echo "WARN  $*"; warn=1; [[ "$STRICT" == "--strict" ]] && hard=1; }

### 1. 目录结构：skills/*/SKILL.md 存在，仓库根目录无 SKILL.md
[[ -f SKILL.md ]] && fail "仓库根目录仍有 SKILL.md（3.x 起 skill 一律在 skills/<name>/）"
shopt -s nullglob
skills=(skills/*/SKILL.md)
[[ ${#skills[@]} -gt 0 ]] || fail "skills/ 下没有任何 SKILL.md"

### 2. 唯一插件清单
[[ -f .claude-plugin/plugin.json ]] || fail "缺 .claude-plugin/plugin.json"
[[ -e .zcode-plugin ]] && fail "存在 .zcode-plugin/（ZCode 也能识别 .claude-plugin，禁止第二份清单）"
[[ -e .codex-plugin ]] && fail "存在 .codex-plugin/（禁止第二份清单）"
pname="$(python3 -c "import json;print(json.load(open('.claude-plugin/plugin.json'))['name'])" 2>/dev/null)" \
  || fail "plugin.json 解析失败"
[[ "${pname:-}" =~ ^[a-z0-9][a-z0-9._-]{0,127}$ ]] || fail "plugin name 不合规: $pname"

### 3. 清单合法性（装有 claude CLI 时走官方校验；否则手动检查其中子项）
if command -v claude >/dev/null 2>&1; then
  if out="$(claude plugin validate "$REPO_ROOT" 2>&1)"; then
    echo "INFO  claude plugin validate: passed（完整输出如下，warning 原样透出）"
    echo "$out" | sed 's/^/      /'
  else
    fail "claude plugin validate 未通过: $(echo "$out" | tail -3)"
  fi
else
  warnn "claude 不在 PATH，跳过官方校验（改为自检 owner、路径等子项）"
fi
python3 - <<'PY' || hard=1
import json, sys
m = json.load(open('.claude-plugin/marketplace.json'))
if 'owner' not in m: print("FAIL  marketplace.json 缺 owner（Claude 端必填）"); sys.exit(1)
p = json.load(open('.claude-plugin/plugin.json'))
for key in ('skills','commands','hooks','mcpServers','agents'):
    v = p.get(key)
    if isinstance(v, str):
        if not v.startswith('./'): print(f"FAIL  plugin.json {key} 路径必须以 ./ 开头: {v}"); sys.exit(1)
        if '..' in v: print(f"FAIL  plugin.json {key} 含 ..: {v}"); sys.exit(1)
PY

### 4-5,10. frontmatter 与 description 行数（用 python 逐个 skill 检查）
pyout="$(python3 - "$STRICT" <<'PY'
import sys, re, pathlib
strict = sys.argv[1] == "--strict"
fail = warn = False
desc_lines_total = 0
for f in sorted(pathlib.Path('skills').glob('*/SKILL.md')):
    text = f.read_text()
    m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
    if not m:
        print(f"FAIL  {f}: frontmatter 解析失败"); fail = True; continue
    fm = m.group(1)
    nm = re.search(r'^name:\s*(\S+)', fm, re.M)
    if not nm or nm.group(1) != f.parent.name:
        print(f"FAIL  {f}: name 与目录名不一致"); fail = True
    dm = re.search(r'^description: >-\n((?:\s+.*\n?)+)', fm, re.M)
    if not dm:
        print(f"FAIL  {f}: 缺 description"); fail = True; continue
    desc = ' '.join(l.strip() for l in dm.group(1).splitlines())
    n = len(desc)
    if n == 0 or n > 1024:
        print(f"FAIL  {f}: description 长度 {n} 超限（≤1024）"); fail = True
    if not ('触发' in desc[:250] or 'Use ' in desc[:250]):
        print(f"WARN  {f}: 前 250 字符内没有触发词（触发词或 Use when 应放在开头）"); warn = True
    dl = len(dm.group(1).splitlines())
    desc_lines_total += dl
    if 'metadata' in fm and 'version' in fm:
        print(f"FAIL  {f}: frontmatter 带 metadata.version（版本号只写在 plugin.json）"); fail = True
print(f"INFO  description 合计 {desc_lines_total} 行")
if desc_lines_total > 60: print("FAIL  description 合计 >60 行"); fail = True
elif desc_lines_total > 50: print("WARN  description 合计 >50 行（目标 ≤50）"); warn = True
if warn and strict: fail = True
if warn: print("SETWARN")
sys.exit(1 if fail else 0)
PY
)" || hard=1
printf '%s\n' "$pyout" | grep -v '^SETWARN$' || true
# python 级 warning 回写 shell 标志，保证汇总行"（含 warning）"与 WARN 行一致
if printf '%s\n' "$pyout" | grep -q '^SETWARN$'; then
  warn=1
  [[ "$STRICT" == "--strict" ]] && hard=1
fi

### 6. 引用规范：SKILL.md 内禁止 ../；不带安装前缀的 docs/ 引用仅告警
while IFS= read -r -d '' f; do
  if grep -n '\.\./' "$f" >/dev/null; then
    fail "SKILL.md 正文含 ../（对 docs/scripts 的引用一律写 ~/.blue_server_toolkit/ 绝对路径）: $f"
  fi
done < <(find skills -name SKILL.md -print0)
grep -rn '[^~/]docs/[a-z0-9-]*\.md' skills/*/SKILL.md 2>/dev/null | grep -v 'blue_server_toolkit' \
  && warnn "存在不带 ~/.blue_server_toolkit 前缀的 docs/ 引用（见上方输出）" || true

### 7. 契约块：模板与每个 skill 内嵌块逐字节一致
tmpl="$REPO_ROOT/templates/skill-contract.md"
[[ -f "$tmpl" ]] || fail "缺 templates/skill-contract.md"
if [[ -f "$tmpl" ]]; then
  awk '/<!-- BEGIN blue-skill-contract -->/,/<!-- END blue-skill-contract -->/' "$tmpl" > /tmp/.bst-tmpl-block
  for f in "${skills[@]}"; do
    awk '/<!-- BEGIN blue-skill-contract -->/,/<!-- END blue-skill-contract -->/' "$f" > /tmp/.bst-skill-block
    cmp -s /tmp/.bst-tmpl-block /tmp/.bst-skill-block \
      || fail "契约块与模板不一致: $f（改 templates/skill-contract.md 后须把该块复制进全部 skill）"
  done
fi

### 8. 版本号三处一致：plugin.json ↔ README H1 ↔ CHANGELOG 最新条目
v_plugin="$(python3 -c "import json;print(json.load(open('.claude-plugin/plugin.json'))['version'])")"
v_readme="$(head -1 README.md | sed -nE 's/^# Blue Server Toolkit v([0-9]+\.[0-9]+\.[0-9]+)$/\1/p')"
v_log="$(grep -m1 '^## ' CHANGELOG.md | sed -E 's/^## ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
[[ -n "$v_readme" ]] || fail "README H1 不是 '# Blue Server Toolkit vX.Y.Z' 格式"
[[ "$v_plugin" == "$v_readme" && "$v_plugin" == "$v_log" ]] \
  || fail "三处版本号不一致: plugin=$v_plugin readme=$v_readme changelog=$v_log"

### 9. 行数上限：hub ≤400，专项 skill ≤120
for f in "${skills[@]}"; do
  n="$(wc -l < "$f" | tr -d ' ')"
  name="$(basename "$(dirname "$f")")"
  if [[ "$name" == "blue-server-toolkit" ]]; then
    (( n <= 400 )) || fail "hub 行数 $n > 400"
  else
    (( n <= 120 )) || fail "$name 行数 $n > 120"
    grep -q '本 skill 只覆盖' "$f" || fail "$name 缺导航行（正文第 2 行固定指向 hub 路由表）"
  fi
done

### 12. 仓库整洁
git ls-files --error-unmatch config.json >/dev/null 2>&1 && fail "config.json 被追踪"
git ls-files | grep -qx '.DS_Store' && fail ".DS_Store 被追踪"
[[ -n "$(git status --porcelain)" ]] && warnn "工作区不干净（从本地目录安装插件会带入多余文件）"

### 13. 开发软链与插件安装互斥
if [[ -f "$HOME/.zcode/cli/plugins/installed_plugins.json" ]] \
   && grep -q 'blue-server-toolkit' "$HOME/.zcode/cli/plugins/installed_plugins.json"; then
  linked=0
  for base in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills" "$HOME/.zcode/skills"; do
    [[ -e "$base/blue-npu-ops" ]] && linked=1
  done
  (( linked )) && warnn "插件已安装且存在开发软链（会同时加载两份，二选一：--unlink 或卸载插件）"
fi

### 汇总
echo "==="
if (( hard )); then echo "RESULT: FAIL"; exit 1; else echo "RESULT: PASS${warn:+（含 warning）}"; fi
