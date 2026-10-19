#!/bin/sh
set -eu

missing=false
for package in open-iscsi nfs-common cryptsetup dmsetup; do
  if ! dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -qx installed; then
    missing=true
  fi
done

if [ "$missing" = true ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends open-iscsi nfs-common cryptsetup dmsetup
fi

modprobe iscsi_tcp
printf '%s\n' iscsi_tcp > /etc/modules-load.d/longhorn.conf
systemctl enable --now iscsid
mkdir -p /var/lib/longhorn
systemctl is-active --quiet iscsid
command -v iscsiadm
command -v mount.nfs
echo "Longhorn node prerequisites ready"
