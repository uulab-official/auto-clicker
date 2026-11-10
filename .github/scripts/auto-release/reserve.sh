#!/usr/bin/env bash
# Reserve only our own tag and draft after CI has verified the release commit.
set -euo pipefail
[[ "${RELEASE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid release commit' >&2; exit 1; }
[[ "${RELEASE_TAG:-}" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo 'Invalid release tag' >&2; exit 1; }
git fetch --no-tags origin '+refs/heads/main:refs/remotes/origin/main'
if [[ "$(git rev-parse refs/remotes/origin/main)" != "$RELEASE_SHA" ]]; then
  echo 'Main changed after validation; newer push will be considered instead'
  echo 'should_build=false' >> "$GITHUB_OUTPUT"
  exit 0
fi
[[ "v$(node -p "require('./package.json').version")" == "$RELEASE_TAG" ]] || { echo 'Version mismatch' >&2; exit 1; }

# Check release ownership before touching the tag. An unrelated draft can
# reserve a tag name without creating a corresponding git tag yet.
name="Auto Clicker $RELEASE_TAG [auto $RELEASE_SHA]"
releases=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" --jq '.[] | {tag_name,name,draft,prerelease,id}' | jq -s --arg tag "$RELEASE_TAG" '[.[] | select(.tag_name == $tag)]')
count=$(jq 'length' <<< "$releases")
if [[ "$count" == 1 ]]; then
  [[ "$(jq -r '.[0].name' <<< "$releases")" == "$name" ]] || { echo 'Release is not owned by this automation' >&2; exit 1; }
  [[ "$(jq -r '.[0].prerelease' <<< "$releases")" == false ]] || { echo 'Refusing prerelease reuse' >&2; exit 1; }
elif [[ "$count" != 0 ]]; then
  echo 'Multiple releases use the same tag; refusing to modify them' >&2; exit 1
fi
remote_tag=$(git ls-remote --refs origin "refs/tags/$RELEASE_TAG")
if [[ -n "$remote_tag" ]]; then
  git fetch --no-tags origin "refs/tags/$RELEASE_TAG"
  [[ "$(git rev-parse 'FETCH_HEAD^{commit}')" == "$RELEASE_SHA" ]] || { echo 'Tag points to a different commit; refusing to reuse it' >&2; exit 1; }
else
  git push origin "$RELEASE_SHA:refs/tags/$RELEASE_TAG"
fi

if [[ "$count" == 0 ]]; then
  gh release create "$RELEASE_TAG" --verify-tag --draft --title "$name" --notes-file .github/scripts/auto-release/release-notes.md
elif [[ "$count" == 1 ]]; then
  if [[ "$(jq -r '.[0].draft' <<< "$releases")" == false ]]; then
    echo 'This exact automated release was already published; nothing to rebuild'
    echo 'should_build=false' >> "$GITHUB_OUTPUT"
    exit 0
  fi
fi
echo 'should_build=true' >> "$GITHUB_OUTPUT"
