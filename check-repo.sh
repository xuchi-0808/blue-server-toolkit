#!/usr/bin/env bash
# check-repo.sh — 3.x 合入门禁：仓形/清单/frontmatter/契约块/版本三镜像/行数预算/卫生。
# 用法：./check-repo.sh [--strict]   退出码 0=通过，1=硬失败；warning 在 --strict 下升级为失败。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
STRICT="${1:-}"
hard=0; warn=0
fail() { echo "FAIL  $*"; hard=1; }
warnn() { echo "WARN  $*"; warn=1; [[ "$STRICT" == "--strict" ]] && hard=1; }

### 1. 仓形：skills/*/SKILL.md 存在，仓根无 SKILL.md
[[ -f SKILL.md ]] && fail "仓根仍有 SKILL.md（3.x 起 skill 一律在 skills/<name>/）"
shopt -s nullglob
skills=(skills/*/SKILL.md)
[[ ${#skills[@]} -gt 0 ]] || fail "skills/ 下没有任何 SKILL.md"

### 2. 单一插件清单
[[ -f .claude-plugin/plugin.json ]] || fail "缺 .claude-plugin/plugin.json"
[[ -e .zcode-plugin ]] && fail "存在 .zcode-plugin/（ZCode 兼容识别 .claude-plugin，禁止双清单）"
[[ -e .codex-plugin ]] && fail "存在 .codex-plugin/（禁止双清单）"
pname="$(python3 -c "import json;print(json.load(open('.claude-plugin/plugin.json'))['name'])" 2>/dev/null)" \
  || fail "plugin.json 解析失败"
[[ "${pname:-}" =~ ^[a-z0-9][a-z0-9._-]{0,127}$ ]] || fail "plugin name 不合规: $pname"

### 3. 清单合法性（claude 可用时走官方校验；否则手动子集）
if command -v claude >/dev/null 2>&1; then
  if out="$(claude plugin validate "$REPO_ROOT" 2>&1)"; then
    echo "INFO  claude plugin validate: passed"
  else
    fail "claude plugin validate 未通过: $(echo "$out" | tail -3)"
  fi
else
  warnn "claude 不在 PATH，跳过官方 validate（自检 owner/路径子集）"
fi
python3 - <<'PY' || hard=1
import json, sys, re
m = json.load(open('.claude-plugin/marketplace.json'))
if 'owner' not in m: print("FAIL  marketplace.json 缺 owner（Claude 端必填）"); sys.exit(1)
p = json.load(open('.claude-plugin/plugin.json'))
for key in ('skills','commands','hooks','mcpServers','agents'):
    v = p.get(key)
    if isinstance(v, str):
        if not v.startswith('./'): print(f"FAIL  plugin.json {key} 路径必须 ./ 开头: {v}"); sys.exit(1)
        if '..' in v: print(f"FAIL  plugin.json {key} 含 ..: {v}"); sys.exit(1)
PY

### 4-5,10. frontmatter / description 预算（python 逐 skill）
python3 - "$STRICT" <<'PY' || hard=1
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
        print(f"WARN  {f}: 前 250 字符无触发语义（触发/Use when 应前置）"); warn = True
    dl = len(dm.group(1).splitlines())
    desc_lines_total += dl
    if 'metadata' in fm and 'version' in fm:
        print(f"FAIL  {f}: frontmatter 带 metadata.version（版本单源是 plugin.json）"); fail = True
print(f"INFO  description 合计 {desc_lines_total} 行")
if desc_lines_total > 60: print(f"FAIL  description 合计 >60 行"); fail = True
elif desc_lines_total > 50: print("WARN  description 合计 >50 行（目标 ≤50）"); warn = True
if warn and strict: fail = True
sys.exit(1 if fail else 0)
PY

### 6. 引用规范：SKILL.md 内 ../ 零容忍；仓内 docs/ 裸引用仅告警
while IFS= read -r -d '' f; do
  if grep -n '\.\./' "$f" >/dev/null; then
    fail "SKILL.md 正文含 ../（资产引用一律 ~/.blue_server_toolkit/ 绝对路径）: $f"
  fi
done < <(find skills -name SKILL.md -print0)
grep -rn '[^~/]docs/[a-z0-9-]*\.md' skills/*/SKILL.md 2>/dev/null | grep -v 'blue_server_toolkit' \
  && warnn "存在非 ~/.blue_server_toolkit 前缀的 docs/ 引用（见上）" || true

### 7. 契约块：模板单源与每个 skill 内嵌块逐字节一致
tmpl="$REPO_ROOT/templates/skill-contract.md"
[[ -f "$tmpl" ]] || fail "缺 templates/skill-contract.md"
if [[ -f "$tmpl" ]]; then
  awk '/<!-- BEGIN blue-skill-contract -->/,/<!-- END blue-skill-contract -->/' "$tmpl" > /tmp/.bst-tmpl-block
  for f in "${skills[@]}"; do
    awk '/<!-- BEGIN blue-skill-contract -->/,/<!-- END blue-skill-contract -->/' "$f" > /tmp/.bst-skill-block
    cmp -s /tmp/.bst-tmpl-block /tmp/.bst-skill-block \
      || fail "契约块与单源不一致: $f（改 templates/skill-contract.md 后须同步全部 skill）"
  done
fi

### 8. 版本三镜像：plugin.json ↔ README H1 ↔ CHANGELOG 头条
v_plugin="$(python3 -c "import json;print(json.load(open('.claude-plugin/plugin.json'))['version'])")"
v_readme="$(head -1 README.md | sed -nE 's/^# Blue Server Toolkit v([0-9]+\.[0-9]+\.[0-9]+)$/\1/p')"
v_log="$(grep -m1 '^## ' CHANGELOG.md | sed -E 's/^## ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
[[ -n "$v_readme" ]] || fail "README H1 不是 '# Blue Server Toolkit vX.Y.Z' 格式"
[[ "$v_plugin" == "$v_readme" && "$v_plugin" == "$v_log" ]] \
  || fail "版本三镜像不一致: plugin=$v_plugin readme=$v_readme changelog=$v_log"

### 9. 行数预算：hub ≤400，spoke ≤120
for f in "${skills[@]}"; do
  n="$(wc -l < "$f" | tr -d ' ')"
  name="$(basename "$(dirname "$f")")"
  if [[ "$name" == "blue-server-toolkit" ]]; then
    (( n <= 400 )) || fail "hub 行数 $n > 400"
  else
    (( n <= 120 )) || fail "$name 行数 $n > 120"
    grep -q '本 skill 只覆盖' "$f" || fail "$name 缺逃逸行（第 2 行固定导航指针）"
  fi
done

### 12. 卫生
git ls-files --error-unmatch config.json >/dev/null 2>&1 && fail "config.json 被追踪"
git ls-files | grep -qx '.DS_Store' && fail ".DS_Store 被追踪"
[[ -n "$(git status --porcelain)" ]] && warnn "工作区不干净（本地目录市场安装会带入杂物）"

### 13. 开发链与插件安装互斥
if [[ -f "$HOME/.zcode/cli/plugins/installed_plugins.json" ]] \
   && grep -q 'blue-server-toolkit' "$HOME/.zcode/cli/plugins/installed_plugins.json"; then
  linked=0
  for base in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills" "$HOME/.zcode/skills"; do
    [[ -e "$base/blue-npu-ops" ]] && linked=1
  done
  (( linked )) && warnn "插件已安装且存在开发链（同机会双载，二选一：--unlink 或卸载插件）"
fi

### 汇总
echo "==="
if (( hard )); then echo "RESULT: FAIL"; exit 1; else echo "RESULT: PASS${warn:+（含 warning）}"; fi
