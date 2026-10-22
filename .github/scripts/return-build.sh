#!/usr/bin/env bash
set -euo pipefail
case "$BUILD_PLATFORM" in macos|ios) ;; *) exit 2 ;; esac
branch="codex/client-build-$BUILD_PLATFORM"
output_tree="$RUNNER_TEMP/client-output-$BUILD_PLATFORM"
remote_branch="$(git ls-remote --heads origin "refs/heads/$branch")"
if [[ -n "$remote_branch" ]]; then
  git fetch origin "refs/heads/$branch"
  git worktree add --detach "$output_tree" FETCH_HEAD
else
  git worktree add --orphan -b "$branch" "$output_tree"
fi
output="$output_tree/$BUILD_PLATFORM"
mkdir -p "$output"
find "$output" -mindepth 1 -maxdepth 1 -type f -delete
printf 'Source commit: %s\nRun: https://github.com/%s/actions/runs/%s\n' "$GITHUB_SHA" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID" > "$output/build-source.txt"
for file in client/build/packages/*/"$BUILD_PLATFORM"/*; do
  [[ -f "$file" ]] || continue
  name="$(basename "$file")"
  if [[ "$(stat -f %z "$file")" -gt 104857600 ]]; then
    split -b 94371840 -a 2 "$file" "$output/$name.part-"
  else
    cp "$file" "$output/$name"
  fi
done
git -C "$output_tree" config user.name 'github-actions[bot]'
git -C "$output_tree" config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git -C "$output_tree" add -- "$BUILD_PLATFORM"
git -C "$output_tree" commit -m "Return $BUILD_PLATFORM client build $GITHUB_RUN_ID"
git -C "$output_tree" push origin "HEAD:refs/heads/$branch"
