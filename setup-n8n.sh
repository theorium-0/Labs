#!/usr/bin/env bash
set -e

# ========================================
#  n8n Self-Hosting Setup Script (Ubuntu LTS)
#  Includes: Docker, Traefik (SSL), Firewall, systemd autostart
#  Domain: n8n.thiscorporation.org
# ========================================

# ---- CONFIG ----
N8N_DOMAIN="n8n.thiscorporation.org"
TRAEFIK_EMAIL="admin@thiscorporation.org"
N8N_USER="n8n"
N8N_DATA_DIR="/opt/n8n"
N8N_VERSION="latest"
# ----------------

echo "🚀 Starting full n8n self-host setup for $N8N_DOMAIN..."

# === Update System ===
echo "📦 Updating Ubuntu packages..."
sudo apt update && sudo apt upgrade -y

# === Dependencies ===
echo "🔧 Installing required packages..."
sudo apt install -y curl ca-certificates gnupg lsb-release ufw apt-transport-https

# === Install Docker ===
if ! command -v docker &>/dev/null; then
  echo "🐳 Installing Docker..."
  curl -fsSL https://get.docker.com | sudo bash
fi

# === Install Docker Compose Plugin ===
if ! docker compose version &>/dev/null; then
  echo "🧩 Installing Docker Compose plugin..."
  sudo apt install -y docker-compose-plugin
fi

# === Create n8n User & Directory ===
if ! id "$N8N_USER" &>/dev/null; then
  echo "👤 Creating user '$N8N_USER'..."
  sudo useradd -m -s /bin/bash "$N8N_USER"
fi

sudo mkdir -p "$N8N_DATA_DIR"
sudo chown -R "$N8N_USER":"$N8N_USER" "$N8N_DATA_DIR"
cd "$N8N_DATA_DIR"

# === Generate Encryption Key ===
ENCRYPTION_KEY=$(openssl rand -hex 24)

# === Create docker-compose.yml ===
sudo tee "$N8N_DATA_DIR/docker-compose.yml" > /dev/null <<EOF
version: "3.8"

services:
  traefik:
    image: traefik:v3.1
    container_name: traefik
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.tlschallenge=true"
      - "--certificatesresolvers.myresolver.acme.email=${TRAEFIK_EMAIL}"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./letsencrypt:/letsencrypt"
    restart: always

  n8n:
    image: n8nio/n8n:${N8N_VERSION}
    container_name: n8n
    restart: always
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=changeme
      - N8N_HOST=${N8N_DOMAIN}
      - WEBHOOK_URL=https://${N8N_DOMAIN}/
      - N8N_PORT=5678
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - TZ=$(cat /etc/timezone)
    volumes:
      - n8n_data:/home/node/.n8n
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\`${N8N_DOMAIN}\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=myresolver"
    depends_on:
      - traefik

volumes:
  n8n_data:
EOF

# === Firewall ===
echo "🧱 Configuring UFW firewall..."
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# === Launch n8n Stack ===
echo "🚀 Launching n8n + Traefik Docker stack..."
sudo docker compose up -d

# === Systemd Autostart Service ===
echo "⚙️ Creating systemd service to auto-start on reboot..."
sudo tee /etc/systemd/system/n8n-stack.service > /dev/null <<EOF
[Unit]
Description=n8n Workflow Automation Stack (Docker)
After=docker.service network.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=${N8N_DATA_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable n8n-stack.service

# === Final Summary ===
echo ""
echo "✅ n8n Setup Complete!"
echo "--------------------------------------------"
echo "🌐 Access: https://${N8N_DOMAIN}"
echo "🔐 Default login: admin / changeme"
echo "💾 Data directory: ${N8N_DATA_DIR}"
echo "🔁 Autostart enabled: systemd service 'n8n-stack'"
echo ""
echo "To manage the stack manually:"
echo "  cd ${N8N_DATA_DIR}"
echo "  sudo docker compose logs -f           # View logs"
echo "  sudo docker compose restart n8n       # Restart n8n"
echo "  sudo docker compose pull && sudo docker compose up -d   # Update"
echo ""
echo "To back up data:"
echo "  sudo tar czf ~/n8n-backup-\$(date +%F).tar.gz ${N8N_DATA_DIR}/n8n_data"
echo ""
echo "⚠️  REMINDERS:"
echo "  - Ensure DNS A record points to your server: ${N8N_DOMAIN}"
echo "  - Change default password immediately!"
echo "  - Check HTTPS status with: sudo docker compose logs traefik"
echo ""
echo "🎉 Setup finished successfully!"
