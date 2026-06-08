#!/usr/bin/env bash
# provision-robot-router.sh — inject per-robot identity into a freshly flashed
# GL robot router (openwrt `robot` profile) and apply it.
#
# Fleet convention (zero lookup):
#   robot N  ->  jump host coscene-eva-N, mesh IP 10.144.145.N, node eva-N-router
#   router reached at 192.168.8.1 through the robot's eth0 (ProxyJump).
#
# Usage:
#   provision-robot-router.sh <robot-num> [wifi_ssid] [wifi_key]
#   e.g. provision-robot-router.sh 46
#        provision-robot-router.sh 46 coScene-Robot 99999999
set -euo pipefail

N="${1:?robot number required, e.g. 46}"
SSID="${2:-coScene-Robot}"
KEY="${3:-99999999}"

NODE="eva-${N}-router"
MESH="10.144.145.${N}"
JUMP="coscene-eva-${N}"
ROUTER="192.168.8.1"
IDENT="${HOME}/.ssh/keys/coscene-dev"

SSH="ssh -J ${JUMP} -i ${IDENT} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 root@${ROUTER}"

echo "Provisioning ${NODE} (mesh ${MESH}) via ${JUMP} -> ${ROUTER} ..."

$SSH "cat > /etc/glrobot.conf" <<EOF
# Provisioned by provision-robot-router.sh on $(date -u +%Y-%m-%dT%H:%MZ)
NODE_NAME="${NODE}"
MESH_IP="${MESH}"
WIFI_SSID="${SSID}"
WIFI_KEY="${KEY}"
EOF

$SSH "/usr/sbin/glrobot-provision"
echo "Done. Verify: $SSH 'uci get system.@system[0].hostname; cat /etc/easytier/config.toml | grep -E \"hostname|ipv4\"'"
