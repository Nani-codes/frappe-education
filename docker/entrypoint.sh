#!/bin/bash
set -e

# Coolify/Docker named volumes are root-owned; bench runs as frappe
mkdir -p /home/frappe/data
chown -R frappe:frappe /home/frappe/data

export HOME=/home/frappe
cd /home/frappe

if command -v runuser >/dev/null 2>&1; then
	exec runuser -u frappe -- bash /workspace/init.sh
fi

exec su --preserve-environment -s /bin/bash frappe -c "bash /workspace/init.sh"
