#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_ROOT"
dest="$REPO_ROOT/native/stable-diffusion.cpp"
if [[ -e "$dest" ]]; then
  echo "Already present"
  exit 0
fi
git clone --depth 1 https://github.com/leejet/stable-diffusion.cpp "$dest"
# Pin to a specific tag after first fetch: git -C native/stable-diffusion.cpp checkout <tag>
echo "stable-diffusion.cpp ready."
