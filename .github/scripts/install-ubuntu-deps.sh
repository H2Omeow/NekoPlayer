#!/usr/bin/env bash
# Installs Ubuntu packages for release builds. Canonical's archive DNS and the
# hosted-runner image mirror have been unreliable, so try independent mirrors
# and only stop after one both refreshes its index and downloads every package.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <package> [package...]" >&2
  exit 2
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_SUSPEND=1
sudo systemctl stop unattended-upgrades.service apt-daily.service apt-daily-upgrade.service 2>/dev/null || true

. /etc/os-release
codename="${VERSION_CODENAME:-jammy}"

case "$(uname -m)" in
  aarch64|arm64)
    mirrors=(
      http://mirror.leaseweb.com/ubuntu-ports
      http://mirrors.ocf.berkeley.edu/ubuntu-ports
      http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports
      http://mirrors.ustc.edu.cn/ubuntu-ports
    )
    ;;
  *)
    mirrors=(
      http://mirror.enzu.com/ubuntu
      http://mirror.math.princeton.edu/pub/ubuntu
      http://mirrors.edge.kernel.org/ubuntu
    )
    ;;
esac

source_file=sources.list.d/nekoplayer-release.list
update_options=(
  -o "Dir::Etc::sourcelist=$source_file"
  -o "Dir::Etc::sourceparts=-"
  -o "Acquire::ForceIPv4=true"
  -o "Acquire::Retries=1"
  -o "Acquire::http::Timeout=10"
  -o "Acquire::https::Timeout=10"
  -o "Acquire::http::Pipeline-Depth=0"
  -o "DPkg::Lock::Timeout=120"
)
install_options=(
  -o "Dir::Etc::sourcelist=$source_file"
  -o "Dir::Etc::sourceparts=-"
  -o "Acquire::ForceIPv4=true"
  -o "Acquire::Retries=3"
  -o "Acquire::http::Timeout=20"
  -o "Acquire::https::Timeout=20"
  -o "Acquire::http::Pipeline-Depth=0"
  -o "DPkg::Lock::Timeout=120"
)

for mirror in "${mirrors[@]}"; do
  echo "Trying Ubuntu mirror $mirror"
  sudo rm -rf /var/lib/apt/lists/*
  {
    echo "deb $mirror $codename main restricted universe multiverse"
    echo "deb $mirror $codename-updates main restricted universe multiverse"
    echo "deb $mirror $codename-security main restricted universe multiverse"
  } | sudo tee "/etc/apt/$source_file" >/dev/null
  if timeout 120 sudo apt-get update "${update_options[@]}" &&
     timeout 600 sudo apt-get install -y "${install_options[@]}" "$@"; then
    echo "Installed packages from $mirror"
    exit 0
  fi
  echo "::warning::Ubuntu mirror $mirror failed; trying the next one"
  sudo apt-get clean || true
done

echo "::error::No usable Ubuntu mirror for $codename"
exit 1
