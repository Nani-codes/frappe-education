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
DATA_DIR="/home/frappe/data"
BENCH_DIR="${DATA_DIR}/frappe-bench"

if [ -d "${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin" ]; then
	export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin:${PATH}"
fi

# Newer mysql/mariadb clients require TLS; our MariaDB container has no SSL
cat > "${HOME}/.my.cnf" <<'EOF'
[client]
host=mariadb
ssl=0
skip-ssl
EOF
chmod 600 "${HOME}/.my.cnf"

bench_ready() {
	[ -d "${BENCH_DIR}/apps/frappe" ] && [ -f "${BENCH_DIR}/sites/common_site_config.json" ]
}

# Partial new-site leaves a directory without a working site_config.json
site_ready() {
	[ -f "${BENCH_DIR}/sites/${SITE_NAME}/site_config.json" ]
}

bind_web_to_all_interfaces() {
	# Coolify proxy must reach the container; 127.0.0.1 alone is unreachable
	if [ -f Procfile ]; then
		sed -i 's/bench serve/bench serve --host 0.0.0.0/g' Procfile
		# avoid duplicating the flag on restarts
		sed -i 's/--host 0.0.0.0 --host 0.0.0.0/--host 0.0.0.0/g' Procfile
	fi
}

start_bench() {
	echo "Starting bench on site: ${SITE_NAME}"
	cd "${BENCH_DIR}"
	bind_web_to_all_interfaces
	bench use "${SITE_NAME}" || true
	echo "=== Web must listen on 0.0.0.0:8000 for Coolify ==="
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
bind_web_to_all_interfaces

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
	# Remove broken partial site from a previous SSL/password failure
	rm -rf "${BENCH_DIR}/sites/${SITE_NAME}"

	if ! bench new-site "${SITE_NAME}" \
		--force \
		--mariadb-root-password "${MYSQL_ROOT_PASSWORD}" \
		--admin-password "${ADMIN_PASSWORD}" \
		--mariadb-user-host-login-scope='%'; then
		echo "FATAL: bench new-site failed (often MariaDB SSL client mismatch or wrong root password)."
		echo "Check the error above. If password-related: delete Coolify volume '*_mariadb-data-v2' and redeploy."
		exit 1
	fi

	bench --site "${SITE_NAME}" install-app erpnext
	bench --site "${SITE_NAME}" install-app education
	bench --site "${SITE_NAME}" set-config developer_mode 1
	bench --site "${SITE_NAME}" enable-scheduler
	bench --site "${SITE_NAME}" clear-cache
fi

bench use "${SITE_NAME}"
echo "=== Setup complete — starting web server on 0.0.0.0:8000 ==="
exec bench start
