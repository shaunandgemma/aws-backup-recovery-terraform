#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "STOP: $*" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail "Run this script with sudo."

expected_volume="${1:-}"
[[ "$expected_volume" =~ ^vol-([0-9a-f]{8}|[0-9a-f]{17})$ ]] ||
    fail "Provide the verified restored EBS volume ID."

# The restored disk must already be mounted.
mountpoint -q /data || fail "/data is not mounted."

data_device="$(findmnt -n -o SOURCE --mountpoint /data)"
actual_serial="$(lsblk -dn -o SERIAL "$data_device" | tr -d '[:space:]')"
expected_serial="${expected_volume//-/}"

[[ "$actual_serial" == "$expected_serial" ]] ||
    fail "/data does not belong to the expected restored volume."

[[ -d /data/orders ]] || fail "The restored orders directory is missing."
[[ -f /data/orders/orders.db ]] || fail "The restored database is missing."

# Match the numeric ownership preserved in this lab's backup.
for path in /data/orders /data/orders/orders.db; do
    [[ "$(stat -c '%u:%g' "$path")" == "993:993" ]] ||
        fail "Unexpected ownership on $path; investigate before continuing."
done

/usr/bin/python3 -c 'import sqlite3; print("SQLite:", sqlite3.sqlite_version)'

# Check for identity conflicts before creating anything.
if getent group orders-app >/dev/null; then
    [[ "$(getent group orders-app | cut -d: -f3)" == "993" ]] ||
        fail "Existing orders-app group has an unexpected GID."
else
    if getent group 993 >/dev/null; then
        fail "GID 993 already belongs to another group."
    fi
fi

if id orders-app >/dev/null 2>&1; then
    [[ "$(id -u orders-app)" == "993" ]] ||
        fail "Existing orders-app user has an unexpected UID."
    [[ "$(id -g orders-app)" == "993" ]] ||
        fail "Existing orders-app user has an unexpected primary GID."
else
    if getent passwd 993 >/dev/null; then
        fail "UID 993 already belongs to another user."
    fi
fi

if ! getent group orders-app >/dev/null; then
    groupadd --system --gid 993 orders-app
fi

if ! id orders-app >/dev/null 2>&1; then
    useradd --system --uid 993 --gid orders-app \
        --no-create-home --shell /sbin/nologin orders-app
fi

install -d -o root -g root -m 0755 /opt/orders-app

sudo -u orders-app test -r /data/orders/orders.db
sudo -u orders-app test -w /data/orders/orders.db
sudo -u orders-app test -w /data/orders
sudo -u orders-app test -x /data/orders

echo "Preparation complete: correct disk, application user and directory."
echo "Application code and service installation are still required."