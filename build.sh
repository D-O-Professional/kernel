#!/usr/bin/env bash
#
# fetch-uek.sh — Fetch or update UEK7-U3 kernel source
#
# Usage: ./fetch-uek.sh [-f <fork-owner>] [-b <branch>] [-d <directory>]
#   -f  Your GitHub user/org for pushing back (default: D-O-Professional)
#   -b  UEK branch to grab    (default: uek7/u3)
#   -d  Target directory      (default: $HOME/kernel)
#

set -euo pipefail
IFS=$'\n\t'

# ─── Defaults ────────────────────────────────────────────────────────────────
FORK="D-O-Professional"
BRANCH="uek7/u3"
TARGET_DIR="$HOME/kernel"
UPSTREAM="https://github.com/oracle/linux-uek.git"
ORIGIN="https://github.com/${FORK}/kernel.git"

# ─── Parse flags ─────────────────────────────────────────────────────────────
while getopts "f:b:d:" opt; do
  case $opt in
    f) FORK=$OPTARG  ; ORIGIN="https://github.com/${FORK}/kernel.git" ;;
    b) BRANCH=$OPTARG ;;
    d) TARGET_DIR=$OPTARG ;;
    *) echo "Usage: $0 [-f <fork-owner>] [-b <branch>] [-d <directory>]" >&2
       exit 1 ;;
  esac
done

# ─── Prerequisites ───────────────────────────────────────────────────────────
for tool in git; do
  if ! command -v $tool &>/dev/null; then
    echo "Error: '$tool' is required but not found. Aborting."
    exit 1
  fi
done

# ─── Update existing clone? ──────────────────────────────────────────────────
if [[ -d "$TARGET_DIR/.git" ]]; then
  echo "→ Found existing repo in $TARGET_DIR. Updating…"
  cd "$TARGET_DIR"

  # Ensure remotes are correct
  git remote set-url upstream "$UPSTREAM" || git remote add upstream "$UPSTREAM"
  git remote set-url origin   "$ORIGIN"   || git remote add origin   "$ORIGIN"

  # Fetch & fast-forward
  git fetch --depth=1 upstream "$BRANCH"
  git checkout -B "${BRANCH##*/}" "upstream/${BRANCH}"
  echo "✔ Updated to $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
  exit 0
fi

# ─── Fresh clone from Oracle upstream ────────────────────────────────────────
echo "→ Cloning UEK branch '${BRANCH}' from Oracle into '$TARGET_DIR'…"
git clone \
  --depth 1 \
  --branch "$BRANCH" \
  "$UPSTREAM" \
  "$TARGET_DIR"

cd "$TARGET_DIR"

# ─── Wire in your fork as 'origin' ───────────────────────────────────────────
echo "→ Adding your fork as 'origin': $ORIGIN"
git remote rename origin upstream
git remote add origin "$ORIGIN"
echo "→ Pushing local ${BRANCH##*/} branch to origin"
git push -u origin HEAD

# ─── Summary ────────────────────────────────────────────────────────────────
echo
echo "✔ Done. Repo is in: $TARGET_DIR"
echo "   Branch: $(git rev-parse --abbrev-ref HEAD)"
echo "   Commit: $(git rev-parse --short HEAD)"
echo
echo "Next steps:"
echo "  1) cd $TARGET_DIR"
echo "  2) modify .config or run 'make menuconfig'"
echo "  3) make -j\$(nproc)"
echo "  4) sudo make modules_install install"
echo "  5) sudo dracut --force && sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
echo
