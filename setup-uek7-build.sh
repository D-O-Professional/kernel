#!/usr/bin/env bash
# setup-uek7-build.sh — Shallow-clone & build UEK7-U3 on Oracle Linux 9
# Usage: ./setup-uek7-build.sh [<fork-owner>] [options]
# Example: ./setup-uek7-build.sh D-O-Professional --no-menuconfig

set -euo pipefail
IFS=$'\n\t'

# — CONFIGURATION —
FORK="${1:-D-O-Professional}"
REPO="kernel"
UEK_BRANCH="uek7/u3"
UPSTREAM="https://github.com/oracle/linux-uek.git"
ORIGIN="https://github.com/${FORK}/${REPO}.git"
WORKDIR="$HOME/${REPO}"
NO_MENUCONFIG=false

# Parse options
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-menuconfig) NO_MENUCONFIG=true ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# — FUNCTIONS —
check_package() {
  if ! rpm -q "$1" &>/dev/null; then
    echo "   → Installing $1"
    sudo dnf install -y "$1"
  else
    echo "   → $1 is already installed"
  fi
}

# — 1. System Prep —
echo "🔧 Preparing system…"
sudo dnf install -y epel-release
sudo dnf update -y

# Install only if not already installed
echo "🔧 Checking and installing build tools…"
check_package git
check_package make
check_package gcc-gnat
check_package flex
check_package bison
check_package xz
check_package bzip2
check_package gcc
check_package g++
check_package ncurses-devel
check_package wget
check_package zlib-devel
check_package patch
check_package innoextract
check_package unzip
check_package python-unversioned-command
check_package sudo

# — 2. Ensure GCC 11 —
GCC_MAJOR=$(gcc -dumpversion | cut -f1 -d.)
if (( GCC_MAJOR < 11 )); then
  echo "⚙️  Detected GCC $GCC_MAJOR, checking for GCC 11…"
  if sudo dnf list -q gcc-toolset-11 &>/dev/null; then
    check_package gcc-toolset-11
    echo "   → Enabling gcc-toolset-11"
    source /opt/rh/gcc-toolset-11/enable
  elif sudo dnf list -q gcc11 &>/dev/null; then
    check_package gcc11
    check_package gcc11-c++
    export CC=gcc11 CXX=g++11
  else
    echo "❌ GCC 11 not found. Please install GCC 11 or later."
    exit 1
  fi
else
  echo "✅ Using $(gcc --version | head -n1)"
fi

# — 3. Clone your fork shallow with UEK7-U3 —
echo "📥 Cloning ${REPO}@${UEK_BRANCH} from your fork…"
if [[ ! -d "$WORKDIR" ]]; then
  git clone --depth 1 \
    --branch "$UEK_BRANCH" \
    "$ORIGIN" \
    "$WORKDIR" || {
    echo "❌ Failed to.Fetch from upstream clone repository. Check network or repository URL."
    exit 1
  }
else
  echo "   → $WORKDIR exists, skipping clone"
fi
cd "$WORKDIR"

# — 4. Add Oracle upstream & fetch UEK7-U3 tip —
echo "🔗 Adding upstream and fetching UEK7-U3…"
if ! git remote | grep -q upstream; then
  git remote add upstream "$UPSTREAM"
fi
# bump buffers to avoid network hiccups
git -c http.postBuffer=524288000 \
    fetch --depth 1 upstream "$UEK_BRANCH" || {
  echo "❌ Failed to fetch from upstream. Check network or branch name."
  exit 1
}

# — 5. Checkout local tracking branch —
echo "🌿 Checking out local branch uek7-u3…"
git checkout -B uek7-u3 upstream/"$UEK_BRANCH"

# — 6. Import existing config —
echo "⚙️  Importing current kernel config…"
if [[ -f /proc/config.gz ]]; then
  zcat /proc/config.gz > .config
elif [[ -f /boot/config-$(uname -r) ]]; then
  cp /boot/config-$(uname -r) .config
else
  echo "   → No existing config found, running defconfig"
  make defconfig
fi

# — 7. Interactive config —
if [[ "$NO_MENUCONFIG" = false ]]; then
  echo "🛠️  Launching menuconfig—tweak drivers now…"
  make menuconfig
else
  echo "   → Skipping menuconfig as requested"
fi

# — 8. Build & install —
echo "🚧 Building kernel + your patches…"
make -j"$(nproc)" || {
  echo "❌ Kernel build failed. Check error messages above."
  exit 1
}

echo "📦 Installing modules & kernel…"
sudo make modules_install install || {
  echo "❌ Installation failed. Check permissions or disk space."
  exit 1
}

echo "🔄 Rebuilding initramfs…"
sudo dracut --force || {
  echo "❌ Initramfs rebuild failed."
  exit 1
}

echo "✅ Updating GRUB…"
sudo grub2-mkconfig -o /boot/grub2/grub.cfg || {
  echo "❌ GRUB update failed."
  exit 1
}

echo -e "\n🎉 Done! Reboot into ‘uek7-u3’ to test your changes."