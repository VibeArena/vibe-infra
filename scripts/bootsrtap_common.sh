#!/usr/bin/env bash
set -euo pipefail

# Install Docker & Compose plugin, setup basics (Ubuntu)
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release ufw

# Docker repo
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# docker group
sudo usermod -aG docker $USER

# Firewall
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
# Core VM에서 Prometheus/Grafana/Loki/OTel를 내부 관리망에서만 쓰려면, 보안그룹/방화벽으로 접근 제한하세요.
sudo ufw --force enable

echo "Docker & UFW installed. Re-login for docker group to apply."
