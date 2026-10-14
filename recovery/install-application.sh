#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "STOP: $*" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail "Run this script with sudo."

expected_volume="${1:-}"
[[ -n "$expected_volume" ]] ||
    fail "Provide the verified restored EBS volume ID."

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname -- "$script_dir")"

app_source="$project_dir/app/app.py"
service_source="$project_dir/app/orders-app.service"

[[ -f "$app_source" ]] || fail "Application source is missing."
[[ -f "$service_source" ]] || fail "Service definition is missing."

# Avoid replacing files underneath an application that is already running.
if systemctl is-active --quiet orders-app; then
    fail "orders-app is running. Review and approve an update separately."
fi

# Validate the Python source without running the application.
 /usr/bin/python3 - "$app_source" <<'PY'
import ast
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
ast.parse(source.read_text(encoding="utf-8"), filename=str(source))
print("Python syntax check passed.")
PY

# Verify the mounted disk and prepare the application identity.
bash "$script_dir/prepare-server.sh" "$expected_volume"

install -o root -g root -m 0644 \
    "$app_source" /opt/orders-app/app.py

install -o root -g root -m 0644 \
    "$service_source" /etc/systemd/system/orders-app.service

systemctl daemon-reload
systemctl enable --now orders-app

echo "Application installed and service start requested."
echo "Verify health, recovered orders and database integrity next."