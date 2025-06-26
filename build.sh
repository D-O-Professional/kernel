#!/usr/bin/env bash
# setup-uek7-build.sh — Shallow-clone & build UEK7-U3 on Oracle Linux 9
# Usage: ./setup-uek7-build.sh [<fork-owner>]
# Example: ./setup-uek7-build.sh D-O-Professional

set -euo pipefail
IFS=$'\n\t'

# — CONFIGURATION —
FORK="${1:-D-O-Professional}"
REPO="kernel"
UEK_BRANCH="uek7/u3"
UPSTREAM="https://github.com/oracle/linux-uek.git"
ORIGIN="https://github.com/${FORK}/${REPO}.git"
WORKDIR="$HOME/${REPO}"

# — 1. System Prep —
echo "🔧 Installing EPEL, updating & core build tools…"
sudo dnf install -y epel-release
sudo dnf update -y
sudo dnf install -y \
  git make gcc-gnat flex bison xz bzip2 \
  gcc g++ ncurses-devel wget zlib-devel \
  patch innoextract unzip python-unversioned-command sudo

# — 2. Ensure GCC 11 —
GCC_MAJOR=$(gcc -dumpversion | cut -f1 -d.)
if (( GCC_MAJOR < 11 )); then
  echo "⚙️  Detected GCC $GCC_MAJOR, installing GCC 11…"
  if sudo dnf list -q gcc-toolset-11 &>/dev/null; then
    sudo dnf install -y gcc-toolset-11
    echo "   → Enabling gcc-toolset-11"
    source /opt/rh/gcc-toolset-11/enable
  else
    sudo dnf install -y gcc11 gcc11-c++
    export CC=gcc11 CXX=g++11
  fi
fi
echo "✅ Using $(gcc --version | head -n1)"

# — 3. Clone your fork shallow with UEK7-U3 —
echo "📥 Cloning ${REPO}@${UEK_BRANCH} from your fork…"
if [[ ! -d "$WORKDIR" ]]; then
  git clone --depth 1 \
    --branch "$UEK_BRANCH" \
    "$ORIGIN" \
    "$WORKDIR"
else
  echo "   → $WORKDIR exists, skipping clone"
fi
cd "$WORKDIR"

# — 4. Add Oracle upstream & fetch UEK7-U3 tip —
echo "🔗 Adding upstream and fetching UEK7-U3…"
if ! git remote | grep -q upstream; then
  git remote add upstream "$UPSTREAM"
fi
# bump buffers to avoid network hiccups
git -c http.postBuffer=524288000 \
    fetch --depth 1 upstream "$UEK_BRANCH"

# — 5. Checkout local tracking branch —
echo "🌿 Checking out local branch uek7-u3…"
git checkout -B uek7-u3 upstream/"$UEK_BRANCH"

# — 6. Import existing config —
echo "⚙️  Importing current kernel config…"
if [[ -f /proc/config.gz ]]; then
  zcat /proc/config.gz > .config
elif [[ -f /boot/config-$(uname -r) ]]; then
  cp /boot/config-$(uname -r) .config
else
  echo "   → No existing config found, running defconfig"
  make defconfig
fi

# — 7. Interactive config —
echo "🛠️  Launching menuconfig—tweak drivers now…"
make menuconfig

# — 8. Build & install —
echo "🚧 Building kernel + your patches…"
make -j"$(nproc)"

echo "📦 Installing modules & kernel…"
sudo make modules_install install

echo "🔄 Rebuilding initramfs…"
sudo dracut --force

echo "✅ Updating GRUB…"
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

echo -e "\n🎉 Done! Reboot into ‘uek7-u3’ to test your changes."
