#!/usr/bin/env bash
# One-time setup for an Ubuntu 24.04 EC2 instance.
# Run from the cloned repo: ./aws/setup.sh
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/La-Pulga-001/SYE-Lodge.git}"
APP_DIR="${APP_DIR:-/opt/sye-lodge}"
APP_USER="${APP_USER:-syelodge}"
DB_NAME="${DB_NAME:-sye_lodge}"
DB_USER="${DB_USER:-sye_lodge_app}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Detecting public IP"
PUBLIC_IP="$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
if [ -z "$PUBLIC_IP" ]; then
  PUBLIC_IP="localhost"
  echo "Could not detect the EC2 public IP; using http://localhost in email links."
fi

export DEBIAN_FRONTEND=noninteractive
echo "==> Installing system packages"
apt-get update
apt-get install -y ca-certificates curl wget git gnupg nginx postgresql postgresql-contrib \
  openssl fontconfig fonts-dejavu-core

echo "==> Adding a 2 GB swap file for the Maven build"
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> Installing Java 25 (Temurin)"
if ! java -version 2>&1 | grep -q '"25"'; then
  . /etc/os-release
  install -m 0755 -d /usr/share/keyrings
  wget -qO- https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor > /usr/share/keyrings/adoptium.gpg
  echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${VERSION_CODENAME} main" \
    > /etc/apt/sources.list.d/adoptium.list
  apt-get update
  apt-get install -y temurin-25-jdk
fi
java -version

echo "==> Generating database and signing secrets"
DB_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=')"
JWT_SECRET="$(openssl rand -base64 48 | tr -d '\n')"

echo "==> Configuring PostgreSQL"
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN CREATE ROLE ${DB_USER} LOGIN; END IF; END \$\$;"
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'" | grep -q 1; then
  sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
fi

echo "==> Writing /etc/sye-lodge.env"
install -o root -g root -m 0600 /dev/null /etc/sye-lodge.env
cat > /etc/sye-lodge.env <<EOF
SPRING_PROFILES_ACTIVE=prod
DB_HOST=localhost
DB_PORT=5432
DB_NAME=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
JWT_SECRET=${JWT_SECRET}
DEMO_DATA=true
DEMO_PASSWORD=Demo@1234
MAIL_MODE=console
APP_URL=http://${PUBLIC_IP}
JAVA_TOOL_OPTIONS=-Xms128m -Xmx320m -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -XX:MaxMetaspaceSize=128m -XX:ReservedCodeCacheSize=48m -Xss512k -Djava.awt.headless=true
EOF

echo "==> Creating application user"
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  useradd --system --home-dir "${APP_DIR}" --shell /usr/sbin/nologin "${APP_USER}"
fi

echo "==> Cloning and building the application"
rm -rf "${APP_DIR}"
git clone "${REPO_URL}" "${APP_DIR}"
cd "${APP_DIR}"
./mvnw -B -DskipTests package
mkdir -p "${APP_DIR}/uploads" "${APP_DIR}/logs"
chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"

echo "==> Installing the systemd service"
cp "${SCRIPT_DIR}/sye-lodge.service" /etc/systemd/system/sye-lodge.service
systemctl daemon-reload
systemctl enable sye-lodge
systemctl restart sye-lodge

echo "==> Configuring Nginx"
cp "${SCRIPT_DIR}/nginx.conf" /etc/nginx/sites-available/sye-lodge
ln -sf /etc/nginx/sites-available/sye-lodge /etc/nginx/sites-enabled/sye-lodge
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo
echo "==> Done"
echo "Open http://${PUBLIC_IP}"
echo "Follow logs with: sudo journalctl -u sye-lodge -f"
