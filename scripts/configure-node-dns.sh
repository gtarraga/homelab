#!/bin/sh
# Run as root on a node that hosts the Tailnet DNS resolver.
# The node must resolve container registries while its DNS pod is stopped.
set -eu

test "$(id -u)" -eq 0 || { echo 'Run as root on the node.' >&2; exit 1; }
test -x /usr/bin/tailscale
test -d /etc/systemd/system

install -d -m 0755 /usr/local/sbin /etc/systemd/system/tailscaled.service.d
cat > /usr/local/sbin/tailscale-dns-base <<'SCRIPT'
#!/bin/sh
set -eu
tmp=$(mktemp /etc/tailscale-dns-base.XXXXXX)
trap 'rm -f "$tmp"' EXIT HUP INT TERM
cat > "$tmp" <<'DNS'
# Independent node DNS: do not depend on a container running on this node.
nameserver 9.9.9.10
nameserver 1.1.1.1
DNS
chmod 0644 "$tmp"
mv -Tf "$tmp" /etc/resolv.conf
SCRIPT
chmod 0755 /usr/local/sbin/tailscale-dns-base

cat > /etc/systemd/system/tailscaled.service.d/90-local-dns-base.conf <<'UNIT'
[Service]
ExecStartPre=/usr/local/sbin/tailscale-dns-base
UNIT
cat > /etc/systemd/system/tailscaled.service.d/91-bootstrap-dns-policy.conf <<'UNIT'
[Service]
ExecStartPost=/usr/bin/tailscale set --accept-dns=false
UNIT

systemctl daemon-reload
/usr/bin/tailscale set --accept-dns=false
/usr/local/sbin/tailscale-dns-base
getent ahostsv4 registry-1.docker.io >/dev/null
echo 'Independent node DNS installed and registry resolution verified.'
