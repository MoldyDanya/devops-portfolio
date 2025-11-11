#!/bin/bash

set -e

git fetch --prune --prune-tags
git fetch --tags --force --unshallow

echo -e "\nDetailed version info:"
echo "Latest tag: $(git describe --tags --match "v[0-9]*.[0-9]*" --abbrev=0)"
echo "Commits count after tag: $(git rev-list $(git describe --tags --match "v[0-9]*.[0-9]*" --abbrev=0)..HEAD --count)"

# Extract version components
git_describe=$(git describe --tags --match "v[0-9]*.[0-9]*" --long)
tag_version=$(echo "$git_describe" | sed -E 's/v(.*)-[0-9]+-g[a-f0-9]+$/\1/')
commit_count=$(echo "$git_describe" | sed -E 's/v.*-([0-9]+)-g[a-f0-9]+$/\1/')

# Calculate version based on tag format
if [[ "$tag_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
  # MAJOR.MINOR format
  VERSION="${tag_version}.${commit_count}"
  echo "Processing MAJOR.MINOR format: ${tag_version} + ${commit_count} commits = ${VERSION}"
elif [[ "$tag_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  # MAJOR.MINOR.PATCH format
  major_minor=$(echo "$tag_version" | cut -d. -f1-2)
  patch=$(echo "$tag_version" | cut -d. -f3)
  new_patch=$((patch + commit_count))
  VERSION="${major_minor}.${new_patch}"
  echo "Processing MAJOR.MINOR.PATCH format: ${tag_version} + ${commit_count} commits = ${VERSION}"
else
  echo "Error: Unsupported tag format: $tag_version"
  echo "Supported formats are MAJOR.MINOR (e.g., v1.2) or MAJOR.MINOR.PATCH (e.g., v1.2.3)"
  exit 1
fi

echo "Current version: $VERSION"
echo "Tag version: $tag_version"
echo "Commit count: $commit_count"

# Output to GitHub Actions
echo "version=$VERSION" >> $GITHUB_OUTPUT
echo "tag_version=$tag_version" >> $GITHUB_OUTPUT
echo "commit_count=$commit_count" >> $GITHUB_OUTPUT