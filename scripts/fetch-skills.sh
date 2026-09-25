#!/bin/bash
# Downloads the Apple-authored agent skills into .claude/skills/.
# They are not committed: their content belongs to Apple and is not covered by this repo's MIT license.
set -euo pipefail

REPO="https://github.com/superagents-lab/xcode27-skills.git"
COMMIT="6f9ff8d5ad6000491cb0f483a776b7062e41cd97"
SKILLS=(swiftui-specialist swiftui-whats-new-27 test-modernizer audit-xcode-security-settings)

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q
git -C "$tmp" fetch -q --depth 1 "$REPO" "$COMMIT"
git -C "$tmp" checkout -q FETCH_HEAD

mkdir -p "$root/.claude/skills"
for skill in "${SKILLS[@]}"; do
    rm -rf "${root:?}/.claude/skills/$skill"
    cp -R "$tmp/$skill" "$root/.claude/skills/$skill"
    echo "installed $skill"
done
