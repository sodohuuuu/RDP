#!/bin/bash
# ============================================
# 🚀 Windows 11 on Docker + Tailscale RDP
# GitHub Codespaces Edition
# ============================================

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Root chahiye: sudo bash rdp.sh"
  exit 1
fi

WORKDIR="/workspaces/dockercom"
STORAGE="/workspaces/windows-storage"
WIN_USER="SODO"
WIN_PASS="SODOHU@123"

echo "=== 📦 Dependencies install ==="
apt update -y
apt install -y docker-compose-plugin curl wget

systemctl enable docker 2>/dev/null || true
systemctl start docker   2>/dev/null || true

mkdir -p "$WORKDIR" "$STORAGE"
cd "$WORKDIR"

# ── KVM check ───────────────────────────────
KVM_DEV=""
TUN_DEV=""
CAP_NET=""

if [ -e /dev/kvm ]; then
  echo "✅ KVM available"
  KVM_DEV="      - /dev/kvm"
  TUN_DEV="      - /dev/net/tun"
  CAP_NET="    cap_add:\n      - NET_ADMIN"
else
  echo "⚠️  KVM nahi — emulation mode"
fi

echo "=== 🧾 windows.yml bana raha hoon ==="
cat > windows.yml <<EOF
version: "3.9"
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "11"
      USERNAME: "${WIN_USER}"
      PASSWORD: "${WIN_PASS}"
      RAM_SIZE: "4G"
      CPU_CORES: "2"
$([ -n "$KVM_DEV" ] && printf "    devices:\n%s\n%s\n" "$KVM_DEV" "$TUN_DEV")
$([ -n "$CAP_NET"  ] && printf "%b\n" "$CAP_NET")
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
      - "3389:3389/udp"
    volumes:
      - ${STORAGE}:/storage
    restart: always
    stop_grace_period: 2m
EOF

echo "=== 🚀 Windows container start ==="
docker compose -f windows.yml up -d

# ── Tailscale install ────────────────────────
echo "=== 🔵 Tailscale install ==="
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# ── Tailscale start (userspace, Codespaces ke liye) ──
echo "=== 🔵 Tailscale start ==="
tailscaled --tun=userspace-networking \
           --socks5-server=localhost:1055 \
           --outbound-http-proxy-listen=localhost:1055 \
           > /var/log/tailscaled.log 2>&1 &
sleep 3

# ── Auth ────────────────────────────────────
echo
echo "==================================================="
echo "👉 Tailscale login ke liye neeche link khulega:"
echo "   (browser mein open karo aur approve karo)"
echo "==================================================="
tailscale up --accept-routes 2>&1 | grep -o "https://.*" | head -n 1 || \
tailscale up --accept-routes

sleep 5

# ── IP fetch ────────────────────────────────
TS_IP=$(tailscale ip -4 2>/dev/null || echo "")

echo
echo "=============================================="
echo "🎉 Setup Complete!"
echo
echo "🌍 Web Console (NoVNC) — Codespace port 8006 forward karo"
echo
if [ -n "$TS_IP" ]; then
  echo "🖥️  RDP via Tailscale:"
  echo "    IP   : ${TS_IP}"
  echo "    Port : 3389"
  echo
  echo "    👉 Windows RDP app mein type karo:"
  echo "    ${TS_IP}:3389"
else
  echo "⚠️  Tailscale IP nahi mili — check karo: tailscale ip -4"
fi
echo
echo "🔑 Username : ${WIN_USER}"
echo "🔒 Password : ${WIN_PASS}"
echo
echo "── Commands ──────────────────────────────────"
echo "  docker logs -f windows     # Windows boot dekho"
echo "  tailscale status           # Tailscale check"
echo "  tailscale ip -4            # IP dobara dekho"
echo "=============================================="
