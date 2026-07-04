#!/bin/bash
set -e

echo "=== Central Jenkinsfile Updater ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ORG="bit-toolnest"

TEMPLATE_ORG="bit-template"
TEMPLATE_REPO="tool-template"

SOURCE_FILE="Jenkinsfile"
TARGET_FILE="Jenkinsfile"

COMMIT_MESSAGE="Central update: Jenkinsfile synchronized"

EXCLUDE_REPOS=(
    "repo_updater"
)

echo "[INFO] Checking environment..."

if [[ -z "$ADMIN_USER" ]]; then
    echo "[ERROR] ADMIN_USER missing"
    exit 1
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "[ERROR] GITHUB_TOKEN missing"
    exit 1
fi

WORKDIR=$(mktemp -d)

cleanup() {
    rm -rf "$WORKDIR"
}

trap cleanup EXIT

echo "[INFO] Cloning template repository..."

git clone \
"https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${TEMPLATE_ORG}/${TEMPLATE_REPO}.git" \
"${WORKDIR}/template"

SOURCE_PATH="${WORKDIR}/template/${SOURCE_FILE}"

if [[ ! -f "$SOURCE_PATH" ]]; then
    echo "[ERROR] Jenkinsfile not found in template repository"
    exit 1
fi

echo "[INFO] Fetching repositories from ${ORG}..."

REPOS=$(
curl -s \
-H "Authorization: token ${GITHUB_TOKEN}" \
"https://api.github.com/orgs/${ORG}/repos?per_page=100" |
grep '"name"' |
cut -d '"' -f4
)

for repo in $REPOS
do

    skip=false

    for excluded in "${EXCLUDE_REPOS[@]}"
    do
        if [[ "$repo" == "$excluded" ]]
        then
            skip=true
            break
        fi
    done

    if [[ "$skip" == true ]]
    then
        echo "[INFO] Skipping ${repo}"
        continue
    fi

    echo ""
    echo "[INFO] Updating ${repo}"

    TEMP_REPO="${WORKDIR}/${repo}"

    git clone \
    "https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${ORG}/${repo}.git" \
    "${TEMP_REPO}"

    cp "${SOURCE_PATH}" \
       "${TEMP_REPO}/${TARGET_FILE}"

    cd "${TEMP_REPO}"

    git config user.name "jenkins"
    git config user.email "jenkins@bit-toolnest.local"

    git add "${TARGET_FILE}"

    if git diff --cached --quiet
    then
        echo "[INFO] No changes detected for ${repo}"
        cd "$WORKDIR"
        continue
    fi

    git commit -m "${COMMIT_MESSAGE}" || true

    git push

    echo "[INFO] ${repo} updated"

    cd "$WORKDIR"

done

echo ""
echo "✅ Update process completed"
