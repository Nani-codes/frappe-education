#!/bin/bash
set -eo pipefail

# Non-interactive shells don't load .bashrc; pull nvm/node from the bench image if present
if [ -f "$HOME/.bashrc" ]; then
	# shellcheck disable=SC1091
	source "$HOME/.bashrc" || true
fi
if [ -f "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
	# shellcheck disable=SC1091
	source "${NVM_DIR:-$HOME/.nvm}/nvm.sh" || true
fi

SITE_NAME="${SITE_NAME:-education.localhost}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-123}"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NODE_VERSION_DEVELOP="${NODE_VERSION_DEVELOP:-18}"

if [ -d "${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin" ]; then
	export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin:${PATH}"
fi

if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
	echo "Bench already exists, starting..."
	cd /home/frappe/frappe-bench
	bench use "${SITE_NAME}" || true
	exec bench start
fi

echo "Creating new bench for site: ${SITE_NAME}"

bench init --skip-redis-config-generation frappe-bench
cd frappe-bench

# Use containers instead of localhost
bench set-mariadb-host mariadb
bench set-redis-cache-host redis://redis:6379
bench set-redis-queue-host redis://redis:6379
bench set-redis-socketio-host redis://redis:6379

# Remove redis, watch from Procfile
sed -i '/redis/d' ./Procfile
sed -i '/watch/d' ./Procfile

bench get-app erpnext
bench get-app education

bench new-site "${SITE_NAME}" \
	--force \
	--mariadb-root-password "${MYSQL_ROOT_PASSWORD}" \
	--admin-password "${ADMIN_PASSWORD}" \
	--no-mariadb-socket

bench --site "${SITE_NAME}" install-app erpnext
bench --site "${SITE_NAME}" install-app education
bench --site "${SITE_NAME}" set-config developer_mode 1
bench --site "${SITE_NAME}" enable-scheduler
bench --site "${SITE_NAME}" clear-cache
bench use "${SITE_NAME}"

exec bench start
