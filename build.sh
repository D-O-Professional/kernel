#!/usr/bin/env bash
# setup-uek7-build.sh — Provision Oracle Linux 9 on Termux, fetch UEK7, build & install
# Usage: ./setup-uek7-build.sh [<fork-owner>]
# Example: ./setup-uek7-build.sh D-O-Professional

set -euo pipefail
IFS=$'\n\t'

# — Configuration —
FORK_OWNER="${1:-D-O-Professional}"
UEK_BRANCH="uekr7"
REPO_NAME="kernel"
REPO_URL="https://github.com/${FORK_OWNER}/${REPO_NAME}.git"
UPSTREAM_URL="https://github.com/oracle/linux-uek.git"
WORKDIR="$HOME/${REPO_NAME}"

# — Step 0: prerequisites —
echo "1️⃣  Installing build dependencies…"
sudo dnf update -y
sudo dnf install -y \
  gcc-toolset-11 make bc elfutils-libelf-devel \
  ncurses-devel dracut grub2-tools git \
  kernel-uek-devel sudo

# enable GCC 11
echo "   → Enabling gcc-toolset-11"
source /opt/rh/gcc-toolset-11/enable

# — Step 1: clone your fork —
echo "2️⃣  Cloning your shallow fork (${UEK_BRANCH})…"
if [[ -d "$WORKDIR" ]]; then
  echo "   ⚠️  Directory $WORKDIR exists, skipping clone."
else
  git clone \
    --depth 1 \
    --branch "${UEK_BRANCH}" \
    "${REPO_URL}" \
    "${WORKDIR}"
fi
cd "$WORKDIR"

# — Step 2: add & fetch upstream UEK7 —
echo "3️⃣  Adding upstream and fetching UEK7 tip…"
if ! git remote | grep -q upstream; then
  git remote add upstream "${UPSTREAM_URL}"
fi
git fetch --depth 1 upstream "${UEK_BRANCH}"

# — Step 3: checkout UEK7 tracking branch —
echo "4️⃣  Checking out local branch ${UEK_BRANCH}…"
git checkout -B "${UEK_BRANCH}" upstream/"${UEK_BRANCH}"

# — Step 4: import current running config —
echo "5️⃣  Importing existing kernel config…"
if [[ -e /proc/config.gz ]]; then
  zcat /proc/config.gz > .config
elif [[ -e /boot/config-$(uname -r) ]]; then
  cp /boot/config-$(uname -r) .config
else
  echo "   ⚠️  No existing config found, generating default."
  make defconfig
fi

# — Step 5: interactive config (optional) —
echo "6️⃣  Launching menuconfig (modify drivers as needed)…"
make menuconfig

# — Step 6: compile & install —
echo "7️⃣  Building UEK7 + your patches…"
make -j"$(nproc)"

echo "8️⃣  Installing modules & kernel…"
sudo make modules_install install

echo "9️⃣  Rebuilding initramfs…"
sudo dracut --force

echo "🔟  Updating GRUB configuration…"
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

echo ""
echo "🎉 Build & install complete!"
echo "Reboot into your new UEK7 kernel to test your driver changes."
