#!/bin/bash
set -e

PART=$1
VERSION=$(cat VERSION)
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

case "$PART" in
  major)
    MAJOR=$((MAJOR+1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR+1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH+1))
    ;;
  *)
    echo "Usage: $0 {major|minor|patch}"
    exit 1
    ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
echo $NEW_VERSION > VERSION

echo "Version updated: $VERSION → $NEW_VERSION"
echo "Don't forget to update CHANGELOG.md"
