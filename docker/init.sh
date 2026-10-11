#!/bin/bash
set -eo pipefail

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
# Bench lives under the volume mount so `bench init` can create the directory
DATA_DIR="/home/frappe/data"
BENCH_DIR="${DATA_DIR}/frappe-bench"

if [ -d "${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin" ]; then
	export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin:${PATH}"
fi

bench_ready() {
	[ -d "${BENCH_DIR}/apps/frappe" ] && [ -f "${BENCH_DIR}/sites/common_site_config.json" ]
}

site_ready() {
	[ -d "${BENCH_DIR}/sites/${SITE_NAME}" ]
}

start_bench() {
	echo "Starting bench on site: ${SITE_NAME}"
	cd "${BENCH_DIR}"
	bench use "${SITE_NAME}" || true
	exec bench start
}

if bench_ready && site_ready; then
	start_bench
fi

echo "=== Setup in progress (site will not respond until this finishes) ==="
echo "Creating bench for site: ${SITE_NAME}"

mkdir -p "${DATA_DIR}"
cd "${DATA_DIR}"

if ! bench_ready; then
	# Remove incomplete bench directory (not a volume mount point)
	rm -rf "${BENCH_DIR}"
	bench init --skip-redis-config-generation frappe-bench
fi

cd "${BENCH_DIR}"

mkdir -p sites
if [ ! -f sites/common_site_config.json ]; then
	echo '{}' > sites/common_site_config.json
fi

bench set-mariadb-host mariadb
bench set-redis-cache-host redis://redis:6379
bench set-redis-queue-host redis://redis:6379
bench set-redis-socketio-host redis://redis:6379

sed -i '/redis/d' ./Procfile
sed -i '/watch/d' ./Procfile

if [ ! -d apps/erpnext ]; then
	echo "Installing erpnext (slow)..."
	bench get-app erpnext
fi

if [ ! -d apps/education ]; then
	echo "Installing education (slow)..."
	bench get-app education
fi

if ! site_ready; then
	echo "Creating site ${SITE_NAME}..."
	if ! bench new-site "${SITE_NAME}" \
		--force \
		--mariadb-root-password "${MYSQL_ROOT_PASSWORD}" \
		--admin-password "${ADMIN_PASSWORD}" \
		--no-mariadb-socket; then
		echo "FATAL: MariaDB root password rejected."
		echo "Coolify → stop app → Persistent Storage → delete volume '*_mariadb-data'"
		echo "Then redeploy. Do not change MYSQL_ROOT_PASSWORD after first successful DB init."
		exit 1
	fi

	bench --site "${SITE_NAME}" install-app erpnext
	bench --site "${SITE_NAME}" install-app education
	bench --site "${SITE_NAME}" set-config developer_mode 1
	bench --site "${SITE_NAME}" enable-scheduler
	bench --site "${SITE_NAME}" clear-cache
fi

bench use "${SITE_NAME}"
echo "=== Setup complete — starting web server on :8000 ==="
exec bench start
