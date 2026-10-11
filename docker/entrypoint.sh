#!/bin/bash
set -e

# Coolify/Docker named volumes are root-owned; bench runs as frappe
mkdir -p /home/frappe/frappe-bench
chown -R frappe:frappe /home/frappe/frappe-bench

export HOME=/home/frappe
cd /home/frappe

# Drop root, keep container env (SITE_NAME, passwords, etc.)
if command -v runuser >/dev/null 2>&1; then
	exec runuser -u frappe -- bash /workspace/init.sh
fi

exec su --preserve-environment -s /bin/bash frappe -c "bash /workspace/init.sh"
