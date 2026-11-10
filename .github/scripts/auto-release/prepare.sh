#!/usr/bin/env bash
# Called in a fresh Actions checkout. No tag or release is created here.
set -euo pipefail
[[ "${SOURCE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid source SHA' >&2; exit 1; }
git fetch --no-tags origin '+refs/heads/main:refs/remotes/origin/main'
head=$(git rev-parse refs/remotes/origin/main)

if [[ "$head" != "$SOURCE_SHA" ]]; then
  # A retry is allowed only when our version-only commit is still the exact
  # main head and has the original user commit as its only parent.
  parent=$(git rev-list --parents -n 1 "$head")
  if [[ "$parent" == "$head $SOURCE_SHA" ]] && git log -1 --format=%B "$head" | grep -Fxq "Auto-Release-Source: $SOURCE_SHA"; then
    expected=$(printf '%s\n' package-lock.json package.json src-tauri/Cargo.lock src-tauri/Cargo.toml src-tauri/tauri.conf.json | sort)
    changed=$(git diff-tree --no-commit-id --name-only -r "$head" | sort)
    [[ "$changed" == "$expected" ]] || { echo 'Prior release commit contains unexpected files' >&2; exit 1; }
    git checkout --detach "$head"
    version=$(node -p "require('./package.json').version")
    [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 1
    echo "Reusing version commit $head for $SOURCE_SHA"
  else
    echo "Main has advanced beyond $SOURCE_SHA; the newer push will be processed separately"
    printf 'should_release=false\n' >> "$GITHUB_OUTPUT"
    exit 0
  fi
else
  git checkout --detach "$SOURCE_SHA"
  current=$(node -p "require('./package.json').version")
  # Include release names as well as tags: a draft may reserve a version even
  # when its tag is missing. Never repurpose someone else's draft.
  git ls-remote --tags --refs origin | awk '{sub("refs/tags/", "", $2); print $2}' > "$RUNNER_TEMP/release-refs"
  gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" --jq '.[].tag_name' >> "$RUNNER_TEMP/release-refs"
  version=$(python3 .github/scripts/auto-release/version.py next "$current" "$RUNNER_TEMP/release-refs")
  python3 .github/scripts/auto-release/version.py set "$version"
  git diff --check
  git add package.json package-lock.json src-tauri/Cargo.toml src-tauri/Cargo.lock src-tauri/tauri.conf.json
  git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit -m "chore(release): v$version" -m "Auto-Release-Source: $SOURCE_SHA"
  head=$(git rev-parse HEAD)
  # A regular push is fast-forward only; if another developer pushed in the
  # meantime this fails rather than overwriting that work.
  git push origin "$head:refs/heads/main"
fi

printf 'should_release=true\nrelease_sha=%s\nrelease_tag=v%s\nsource_sha=%s\n' "$head" "$version" "$SOURCE_SHA" >> "$GITHUB_OUTPUT"
