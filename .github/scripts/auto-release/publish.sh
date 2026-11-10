#!/usr/bin/env bash
# Called only after release.yml validates all signed updater assets.
set -euo pipefail
[[ "${RELEASE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || exit 1
[[ "${RELEASE_TAG:-}" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 1
git fetch --no-tags origin '+refs/heads/main:refs/remotes/origin/main'
if [[ "$(git rev-parse refs/remotes/origin/main)" != "$RELEASE_SHA" ]]; then
  echo 'Main advanced during release verification; leaving this release as a draft'
  exit 0
fi
git fetch --no-tags origin "refs/tags/$RELEASE_TAG"
[[ "$(git rev-parse 'FETCH_HEAD^{commit}')" == "$RELEASE_SHA" ]] || { echo 'Release tag changed; refusing publication' >&2; exit 1; }
expected_name="Auto Clicker $RELEASE_TAG [auto $RELEASE_SHA]"
release=$(gh release view "$RELEASE_TAG" --json databaseId,isDraft,isPrerelease,name,tagName)
[[ "$(jq -r .isDraft <<< "$release")" == true && "$(jq -r .isPrerelease <<< "$release")" == false && "$(jq -r .name <<< "$release")" == "$expected_name" && "$(jq -r .tagName <<< "$release")" == "$RELEASE_TAG" ]] || { echo 'Draft ownership or status changed; refusing publication' >&2; exit 1; }

# Never intentionally promote an older version over a newer stable release.
gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' > "$RUNNER_TEMP/published-tags"
previous_tag=$(python3 - "$RELEASE_TAG" "$RUNNER_TEMP/published-tags" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('release_version', '.github/scripts/auto-release/version.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
current = module.parse_version(sys.argv[1])
published = [(v, line) for line in pathlib.Path(sys.argv[2]).read_text().splitlines() if (v := module.parse_version(line))]
if published and max(v for v, _ in published) >= current:
    raise SystemExit('An equal or newer stable version is already published')
if published:
    print(max(published)[1])
PY
)
release_id=$(jq -r .databaseId <<< "$release")
# Generate the changelog from the preceding published stable version, never a
# draft. Keep the safety notice first, and fail closed if notes cannot be made.
jq -n --arg tag "$RELEASE_TAG" --arg target "$RELEASE_SHA" --arg previous "$previous_tag" \
  '{tag_name:$tag,target_commitish:$target} + (if $previous == "" then {} else {previous_tag_name:$previous} end)' > "$RUNNER_TEMP/generate-notes.json"
gh api --method POST "repos/$GITHUB_REPOSITORY/releases/generate-notes" --input "$RUNNER_TEMP/generate-notes.json" > "$RUNNER_TEMP/generated-notes.json"
jq -e '.body | type == "string" and length > 0' "$RUNNER_TEMP/generated-notes.json" > /dev/null || { echo 'GitHub did not generate release notes' >&2; exit 1; }
jq -nr --rawfile safety .github/scripts/auto-release/release-notes.md --slurpfile generated "$RUNNER_TEMP/generated-notes.json" \
  '$safety + "\n---\n\n" + $generated[0].body' > "$RUNNER_TEMP/complete-release-notes.md"
# legacy lets GitHub determine latest using creation date and semver rather
# than force-promoting an older release if another publisher races this run.
jq -n --rawfile notes "$RUNNER_TEMP/complete-release-notes.md" '{draft:false,body:$notes,make_latest:"legacy"}' > "$RUNNER_TEMP/publish-release.json"
remote_head=$(git ls-remote --heads origin refs/heads/main | awk '{print $1}')
if [[ "$remote_head" != "$RELEASE_SHA" ]]; then
  echo 'Main advanced before publication; leaving the release as a draft'
  exit 0
fi
result=$(gh api --method PATCH "repos/$GITHUB_REPOSITORY/releases/$release_id" --input "$RUNNER_TEMP/publish-release.json")
[[ "$(jq -r .draft <<< "$result")" == false && "$(jq -r .tag_name <<< "$result")" == "$RELEASE_TAG" ]] || { echo 'GitHub did not confirm publication' >&2; exit 1; }
jq -e --rawfile notes "$RUNNER_TEMP/complete-release-notes.md" '.body == $notes' <<< "$result" > /dev/null || { echo 'Published notes did not match the required safety notices' >&2; exit 1; }
latest=$(gh api "repos/$GITHUB_REPOSITORY/releases/latest" --jq .tag_name)
[[ "$latest" == "$RELEASE_TAG" ]] || { echo "Release published, but GitHub latest is $latest; investigate concurrent release" >&2; exit 1; }
echo "Published $RELEASE_TAG from verified commit $RELEASE_SHA"
