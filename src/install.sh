#!/bin/bash
set -e

echo "=== Central Repo Sync Tool ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/sync-config.json"

ORG="bit-toolnest"
TEMPLATE_ORG="bit-template"
TEMPLATE_REPO="tool-template"

ADMIN_USER="${ADMIN_USER:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [[ -z "$ADMIN_USER" || -z "$GITHUB_TOKEN" ]]; then
    echo "[ERROR] Missing GitHub credentials."
    exit 1
fi

WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

# --- Load config ---
ORG=$(jq -r '.organization' "$CONFIG_FILE")
TEMPLATE_ORG=$(jq -r '.template_org' "$CONFIG_FILE")
TEMPLATE_REPO=$(jq -r '.template_repo' "$CONFIG_FILE")

UPDATE_MODE=$(jq -r '.update_mode' "$CONFIG_FILE")
PR_TARGET=$(jq -r '.pr_target' "$CONFIG_FILE")
EXCLUDE_REPOS=($(jq -r '.exclude[]' "$CONFIG_FILE"))

# --- Clone template repo ---
echo "[INFO] Cloning template repo..."
git clone "https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${TEMPLATE_ORG}/${TEMPLATE_REPO}.git" "$WORKDIR/template"

# --- Fetch all repos with pagination ---
page=1
REPOS=()
while :; do
  response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/orgs/${ORG}/repos?per_page=100&page=${page}")
  mapfile -t names < <(echo "$response" | jq -r '.[].name')
  [[ ${#names[@]} -eq 0 ]] && break
  REPOS+=("${names[@]}")
  ((page++))
done

# --- Process each repo ---
for repo in "${REPOS[@]}"; do
    if [[ " ${EXCLUDE_REPOS[*]} " =~ " ${repo} " ]]; then
        echo "[INFO] Skipping $repo"
        continue
    fi

    echo "[INFO] Updating $repo..."
    TEMP_REPO="$WORKDIR/$repo"
    git clone "https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${ORG}/${repo}.git" "$TEMP_REPO"
    cd "$TEMP_REPO"

    # --- Sync sources ---
    for row in $(jq -c '.sources[]' "$CONFIG_FILE"); do
        SRC=$(echo "$row" | jq -r '.src')
        DEST=$(echo "$row" | jq -r '.dest')
        TYPE=$(echo "$row" | jq -r '.type')

        SOURCE_PATH="$WORKDIR/template/$SRC"
        TARGET_PATH="$TEMP_REPO/$DEST"

        if [[ "$TYPE" == "file" ]]; then
            if ! diff -q "$SOURCE_PATH" "$TARGET_PATH" >/dev/null 2>&1; then
                cp "$SOURCE_PATH" "$TARGET_PATH"
                git add "$TARGET_PATH"
            fi
        elif [[ "$TYPE" == "folder" ]]; then
            if ! diff -qr "$SOURCE_PATH" "$TARGET_PATH" >/dev/null 2>&1; then
                rsync -a "$SOURCE_PATH/" "$TARGET_PATH/"
                git add "$TARGET_PATH"
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
    git config user.name "sync-bot"
    git config user.email "sync-bot@${ORG}.local"
    echo "===================================="
    echo "PWD: $(pwd)"
    echo "Repo variable: $repo"
    git remote -v
    git branch
    echo "===================================="
    git commit -m "Central update: synchronized [$changed] from template"

    if [[ "$UPDATE_MODE" == "PUSH" ]]; then
        git push origin main
        echo "[INFO] Changes pushed to main"
    else
        branch="sync-update-$(date +%s)"
        git checkout -b "$branch"
        echo "Pushing from:"
        pwd
        git remote get-url origin
        git push origin "$branch"

        curl -s -X POST -H "Authorization: token ${GITHUB_TOKEN}" \
          -d "{\"title\":\"Sync update\",\"head\":\"$branch\",\"base\":\"$PR_TARGET\"}" \
          "https://api.github.com/repos/${ORG}/${repo}/pulls" >/dev/null

        echo "[INFO] PR created for $repo"
    fi

    cd "$WORKDIR"
done

echo "✅ Sync process completed"
