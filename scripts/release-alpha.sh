#!/usr/bin/env bash
set -e

# Sesuaikan MAJOR.MINOR.PATCH untuk rilis ini
BASE_VERSION="v2.0.0"

latest=$(git tag | grep -E "^${BASE_VERSION}-alpha\." | sort -V | tail -n 1 | sed "s/${BASE_VERSION}-alpha.//")

if [ -z "$latest" ]; then
  next=1
else
  next=$((latest + 1))
fi

tag="${BASE_VERSION}-alpha.${next}"

echo "Releasing new alpha tag: ${tag}"

git tag "${tag}"
git push origin "${tag}"

echo "Done."
