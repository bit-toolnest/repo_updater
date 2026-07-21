#!/bin/bash
set -e

echo "=== Central Repo Sync Tool ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/sync-config.json"

# --- Config validation ---
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[ERROR] Missing config file: $CONFIG_FILE"
    exit 1
fi

TARGET_ORG=$(jq -r '.target_org' "$CONFIG_FILE")
SOURCE_ORG=$(jq -r '.source_org' "$CONFIG_FILE")
SOURCE_REPO=$(jq -r '.source_repo' "$CONFIG_FILE")

ADMIN_USER="${ADMIN_USER:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [[ -z "$ADMIN_USER" || -z "$GITHUB_TOKEN" ]]; then
    echo "[ERROR] Missing GitHub credentials."
    exit 1
fi

WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

UPDATE_MODE=$(jq -r '.update_mode' "$CONFIG_FILE")
PR_TARGET=$(jq -r '.pr_target' "$CONFIG_FILE")
EXCLUDE_REPOS=($(jq -r '.exclude[]' "$CONFIG_FILE"))

# --- Dry-run flag ---
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "[INFO] Running in dry-run mode (no commits/pushes/PRs)"
fi

# --- Clone template repo ---
echo "[INFO] Cloning template repo..."
git clone "https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${SOURCE_ORG}/${SOURCE_REPO}.git" "$WORKDIR/template"

# --- Fetch all repos with pagination ---
page=1
REPOS=()
while :; do
  response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/orgs/${TARGET_ORG}/repos?per_page=100&page=${page}")
  mapfile -t names < <(echo "$response" | jq -r '.[].name')
  [[ ${#names[@]} -eq 0 ]] && break
  REPOS+=("${names[@]}")
  ((page++))
done

# --- Process each repo ---
for repo in "${REPOS[@]}"; do
    [[ -z "$repo" ]] && continue

    if [[ " ${EXCLUDE_REPOS[*]} " =~ " ${repo} " ]]; then
        echo "[INFO] Skipping $repo"
        continue
    fi

    echo "[INFO] Updating $repo..."
    TEMP_REPO="$WORKDIR/$repo"
    git clone "https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${TARGET_ORG}/${repo}.git" "$TEMP_REPO"
    cd "$TEMP_REPO"

    # --- Sync sources ---
    for row in $(jq -c '.sources[]' "$CONFIG_FILE"); do
        SRC=$(echo "$row" | jq -r '.src')
        DEST=$(echo "$row" | jq -r '.dest')
        TYPE=$(echo "$row" | jq -r '.type')

        [[ -z "$SRC" ]] && { echo "[WARN] Empty src path in config for $repo"; continue; }
        SOURCE_PATH="$WORKDIR/template/$SRC"
        TARGET_PATH="$TEMP_REPO/$DEST"

        if [[ "$TYPE" == "file" ]]; then
            if ! diff -q "$SOURCE_PATH" "$TARGET_PATH" >/dev/null 2>&1; then
                echo "[DRY-RUN] Would copy file $SRC -> $DEST"
                $DRY_RUN || cp "$SOURCE_PATH" "$TARGET_PATH" && git add "$TARGET_PATH"
            fi
        elif [[ "$TYPE" == "folder" ]]; then
            if ! diff -qr "$SOURCE_PATH" "$TARGET_PATH" >/dev/null 2>&1; then
                echo "[DRY-RUN] Would sync folder $SRC -> $DEST"
                $DRY_RUN || rsync -a "$SOURCE_PATH/" "$TARGET_PATH/" && git add "$TARGET_PATH"
            fi
        fi
    done

    # --- Commit if changes ---
    if git diff --cached --quiet; then
        echo "[INFO] No changes for $repo"
        cd "$WORKDIR"
        continue
    fi

    changed=$(git diff --cached --name-only | tr '\n' ' ')
    tpl_commit=$(git -C "$WORKDIR/template" rev-parse --short HEAD)

    if $DRY_RUN; then
        echo "[DRY-RUN] Would commit: Sync from template@$tpl_commit: updated [$changed]"
        cd "$WORKDIR"
        continue
    fi

    git config user.name "sync-bot"
    git config user.email "sync-bot@${TARGET_ORG}.local"
    git commit -m "Sync from template@$tpl_commit: updated [$changed]"

    # Detect default branch dynamically from target repo
    default_branch=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
      "https://api.github.com/repos/${TARGET_ORG}/${repo}" | jq -r '.default_branch')
    
    if [[ "$UPDATE_MODE" == "PUSH" ]]; then
        git push origin "$default_branch"
        echo "[INFO] Changes pushed to $default_branch"
    else
        branch="sync-update-$(date +%s)"
        git checkout -b "$branch"
        git push origin "$branch"
    
        curl -s -X POST -H "Authorization: token ${GITHUB_TOKEN}" \
          -d "{\"title\":\"Sync update\",\"head\":\"$branch\",\"base\":\"$default_branch\"}" \
          "https://api.github.com/repos/${TARGET_ORG}/${repo}/pulls" >/dev/null
    
        echo "[INFO] PR created for $repo"
    fi

    cd "$WORKDIR"
done

echo "✅ Sync process completed"
