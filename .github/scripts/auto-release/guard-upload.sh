#!/usr/bin/env bash
# Fail closed before any release upload, including manual tag pushes.
set -euo pipefail
[[ "${RELEASE_TAG:-}" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo 'Invalid release tag' >&2; exit 1; }
checked_out=$(git rev-parse HEAD)
expected_sha=${RELEASE_SHA:-$checked_out}
[[ "$expected_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid release commit' >&2; exit 1; }
[[ "$checked_out" == "$expected_sha" ]] || { echo 'Checked-out commit does not match release commit' >&2; exit 1; }
git fetch --no-tags origin "refs/tags/$RELEASE_TAG"
[[ "$(git rev-parse 'FETCH_HEAD^{commit}')" == "$expected_sha" ]] || { echo 'Release tag points to a different commit' >&2; exit 1; }
releases=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" --jq '.[] | {tag_name,draft}' | jq -s --arg tag "$RELEASE_TAG" '[.[] | select(.tag_name == $tag)]')
count=$(jq 'length' <<< "$releases")
if [[ "$count" == 0 ]]; then
  echo 'No existing release; upload may create a draft'
elif [[ "$count" == 1 && "$(jq -r '.[0].draft' <<< "$releases")" == true ]]; then
  echo 'Existing release is a draft'
else
  echo 'Release is public or ambiguous; refusing to upload assets' >&2
  exit 1
fi
