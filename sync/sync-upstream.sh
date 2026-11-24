#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STATE_FILE="sync/upstream-url.txt"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log() { echo "[sync] $*"; }

KNOWN_CANDIDATES=(
  "https://github.com/kangarooking/cangjie-skill.git"
)

AUTH=()
if [ -n "${GH_TOKEN:-}" ]; then
  AUTH=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

probe() {
  local url="$1"
  [ -z "$url" ] && return 1
  git ls-remote "$url" HEAD >/dev/null 2>&1
}

# 1) 作者账号下含 cangjie 的仓库
discover_from_owner() {
  [ -z "${GH_TOKEN:-}" ] && return 0
  local owners=(kangarooking) owner json found
  for owner in "${owners[@]}"; do
    json="$(curl -fsSL --max-time 20 "${AUTH[@]}" \
      "https://api.github.com/users/${owner}/repos?per_page=100&sort=updated" 2>/dev/null || true)"
    [ -z "$json" ] && continue
    found="$(printf '%s' "$json" | python3 -c '
import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(data, list):
    sys.exit(0)
for r in data:
    name = (r.get("name") or "").lower()
    if "cangjie" in name and not r.get("archived"):
        print(r.get("clone_url") or "")
        break
' 2>/dev/null || true)"
    if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
  done
  return 0
}

# 2) 全局搜索 cangjie-skill 仓库
discover_from_search() {
  [ -z "${GH_TOKEN:-}" ] && return 0
  local json found
  json="$(curl -fsSL --max-time 20 "${AUTH[@]}" \
    "https://api.github.com/search/repositories?q=cangjie-skill+in:name&sort=stars&order=desc&per_page=10" 2>/dev/null || true)"
  [ -z "$json" ] && return 0
  found="$(printf '%s' "$json" | python3 -c '
import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in data.get("items", []):
    full = (r.get("full_name") or "").lower()
    if "cangjie" in full and "skill" in full:
        print(r.get("clone_url") or "")
        break
' 2>/dev/null || true)"
  printf '%s' "$found"
}

# 3) 官网链接发现
discover_from_site() {
  local html url
  html="$(curl -fsSL --max-time 20 https://cangjie-skill.com/ 2>/dev/null || true)"
  [ -z "$html" ] && return 0
  url="$(printf '%s' "$html" \
    | grep -oE 'github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' \
    | grep -i 'cangjie' | head -1 || true)"
  [ -n "$url" ] && printf 'https://%s.git' "$url"
  return 0
}

UPSTREAM=""

# 0) 历史记录地址优先
if [ -f "$STATE_FILE" ]; then
  recorded="$(head -1 "$STATE_FILE" | tr -d '[:space:]')"
  if probe "$recorded"; then
    UPSTREAM="$recorded"
    log "records: $UPSTREAM"
  fi
fi

# 1) 已知地址
if [ -z "$UPSTREAM" ]; then
  for c in "${KNOWN_CANDIDATES[@]}"; do
    if probe "$c"; then UPSTREAM="$c"; log "known: $UPSTREAM"; break; fi
  done
fi

# 2) 作者账号
if [ -z "$UPSTREAM" ]; then
  u="$(discover_from_owner || true)"
  if [ -n "$u" ] && probe "$u"; then UPSTREAM="$u"; log "discovered(owner): $UPSTREAM"; fi
fi

# 3) 搜索
if [ -z "$UPSTREAM" ]; then
  u="$(discover_from_search || true)"
  if [ -n "$u" ] && probe "$u"; then UPSTREAM="$u"; log "discovered(search): $UPSTREAM"; fi
fi

# 4) 官网
if [ -z "$UPSTREAM" ]; then
  u="$(discover_from_site || true)"
  if [ -n "$u" ] && probe "$u"; then UPSTREAM="$u"; log "discovered(site): $UPSTREAM"; fi
fi

if [ -z "$UPSTREAM" ]; then
  log "ERROR: upstream not found; keeping current content unchanged"
  exit 1
fi

git clone --depth 1 --quiet "$UPSTREAM" "$WORK/upstream"

# 镜像上游内容，同时保护同步机制自身（.github/ 与 sync/）
rsync -a --delete \
  --exclude '.git' \
  --exclude '.github' \
  --exclude 'sync' \
  "$WORK/upstream/" "$ROOT"/

mkdir -p sync
printf '%s\n' "$UPSTREAM" > "$STATE_FILE"

git add -A
if git diff --cached --quiet; then
  # 上游无变更时保活：GitHub 会在仓库 60 天无提交后停用 scheduled workflow
  # Keep-alive: GitHub disables scheduled workflows after 60 days without commits
  HEARTBEAT="sync/last-check.txt"
  if [ ! -f "$HEARTBEAT" ] || [ -n "$(find "$HEARTBEAT" -mtime +6 2>/dev/null)" ]; then
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$HEARTBEAT"
    git add "$HEARTBEAT"
    git -c user.name="sync-bot" -c user.email="sync-bot@users.noreply.github.com" \
      commit -m "chore: heartbeat $(date -u +%F)" >/dev/null
    git push
    log "no upstream change; heartbeat committed"
  else
    log "already up to date: $UPSTREAM"
  fi
  exit 0
fi

git -c user.name="sync-bot" -c user.email="sync-bot@users.noreply.github.com" \
  commit -m "chore: sync upstream ${UPSTREAM} $(date -u +%Y-%m-%d)" >/dev/null
git push
log "synced: $UPSTREAM"
