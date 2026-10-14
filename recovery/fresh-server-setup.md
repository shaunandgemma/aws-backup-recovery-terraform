# Prepare a fresh recovery server

## Scope

Use this procedure when the recovery EC2 server does not yet have the
application installed.

It assumes the existing lab network, IAM roles and backup resources remain
available. It is not a complete deployment guide for an empty AWS account.

Before proceeding:

- Provision the recovery server through a reviewed Terraform plan.
- Use the project's Amazon Linux configuration and EC2 instance profile.
- Verify the recovery instance ID and Systems Manager access.
- Restore and verify the intended data volume using the recovery runbook.
- Attach that volume to the recovery server in the same Availability Zone.
- Preserve the original server and data disk.

The following steps transfer application files. They do not restore,
format or initialise a database.

## 1 Package the application files

Run in Windows PowerShell from the project directory:

```powershell
$bundleName = "orders-recovery-$([guid]::NewGuid().ToString()).tar.gz"
$bundlePath = Join-Path $env:TEMP $bundleName

tar -czf $bundlePath `
  app/app.py `
  app/orders-app.service `
  recovery/prepare-server.sh `
  recovery/install-application.sh

if ($LASTEXITCODE -ne 0) {
    throw "Application packaging failed."
}

tar -tzf $bundlePath
Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256
```

Verify that the archive contains only the four listed files.
Record its filename and SHA-256 checksum.

The archive deliberately excludes init_db.py, Terraform variables,
credentials and state.

Generate a transfer command and copy it to the clipboard:

```powershell
$bundleBase64 = [Convert]::ToBase64String(
    [System.IO.File]::ReadAllBytes($bundlePath)
)

$transferCommand = "printf '%s' '$bundleBase64' | base64 --decode > '/tmp/$bundleName'"
Set-Clipboard -Value $transferCommand

Write-Output "Linux archive path: /tmp/$bundleName"
```

## 2 Transfer and verify the files

Open a Systems Manager session to the verified recovery instance.
Paste and execute the generated transfer command there.

Set the archive path using the filename printed by PowerShell:

```bash
archive="/tmp/<paste-archive-filename>"
sha256sum "$archive"
```

Compare the checksum with the Windows result. Letter case does not matter.
Stop if the checksums differ.

Inspect the archive:

```bash
tar -tzf "$archive"
```

Confirm the same four relative file paths, then extract into a new
temporary directory without sudo:

```bash
bundle_dir="$(mktemp -d /tmp/orders-recovery.XXXXXX)"
tar -xzf "$archive" -C "$bundle_dir"
printf 'Extracted bundle: %s\n' "$bundle_dir"
```

Check both shell scripts without executing their setup commands:

```bash
bash -n "$bundle_dir/recovery/prepare-server.sh"
bash -n "$bundle_dir/recovery/install-application.sh"
```

Both checks should finish without errors.

Keep this Systems Manager session open and record the extracted directory.
Later commands use the bundle_dir variable.

Do not run the installation script until the correct restored filesystem
has been mounted and its persistent mount configuration has been checked.

## 3 Identify and mount the restored data disk

Run inside the fresh recovery server's Systems Manager session:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,SERIAL
```

Find the disk whose SERIAL matches the restored volume ID, without
the hyphen. Confirm it matches the attachment verified in AWS.

For this lab, the restored data disk has an existing XFS filesystem
directly on the disk, without a partition.

Do not choose the root disk or assume the data disk is always nvme1n1.
Do not attach multiple restored copies with the same filesystem UUID
to this server during this procedure.

Set these variables using the verified values:

```bash
expected_volume="<paste-restored-volume-ID>"
data_device="/dev/<paste-verified-device-name>"
```

For example, a device name might be /dev/nvme1n1, but verify it first.

Inspect the filesystem:

```bash
sudo blkid "$data_device"
```

Expect TYPE="xfs" and an existing UUID. Record that UUID.
If the filesystem is missing or unexpected, investigate. Never format
a disk restored from this backup.

Run this block to check the disk again and mount it:

```bash
(
    set -euo pipefail

    fail() {
        echo "STOP: $*" >&2
        exit 1
    }

    [[ "$expected_volume" =~ ^vol-([0-9a-f]{8}|[0-9a-f]{17})$ ]] ||
        fail "Invalid restored volume ID."

    [[ -b "$data_device" ]] || fail "Device is not a block device."

    actual_serial="$(lsblk -dn -o SERIAL "$data_device" | tr -d '[:space:]')"
    [[ "$actual_serial" == "${expected_volume//-/}" ]] ||
        fail "Device serial does not match the restored volume."

    filesystem="$(sudo blkid -s TYPE -o value "$data_device")"
    [[ "$filesystem" == "xfs" ]] || fail "Expected an existing XFS filesystem."

    if mountpoint -q /data; then
        fail "/data is already mounted; inspect it before continuing."
    fi

    existing_mounts="$(lsblk -nr -o MOUNTPOINTS "$data_device" | tr -d '[:space:]')"
    [[ -z "$existing_mounts" ]] || fail "The selected disk is already mounted."

    sudo mkdir -p /data

    existing_files="$(sudo find /data -mindepth 1 -maxdepth 1 -print -quit)"
    [[ -z "$existing_files" ]] ||
        fail "/data contains files on the root disk; investigate first."

    sudo mount "$data_device" /data
    findmnt --mountpoint /data
)
```

If the block reports an error, stop and investigate.

After a successful mount, verify the restored database exists:

```bash
sudo ls -ln /data/orders/orders.db
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,SERIAL
```

Confirm /data belongs to the expected restored volume.
The database should retain its original numeric ownership.

This mount currently lasts only until shutdown.
The next step configures mounting after reboot.

## 4 Configure mounting after reboot

Continue in the same recovery-server session, before installing or
starting the application.

The following block checks the mounted disk, backs up /etc/fstab,
and adds one /data entry. It stops if an entry already exists.

```bash
(
    set -euo pipefail

    fail() {
        echo "STOP: $*" >&2
        exit 1
    }

    mounted_device="$(findmnt -n -o SOURCE --mountpoint /data)"
    actual_serial="$(lsblk -dn -o SERIAL "$mounted_device" | tr -d '[:space:]')"

    [[ "$actual_serial" == "${expected_volume//-/}" ]] ||
        fail "Mounted disk does not match the expected restored volume."

    filesystem="$(sudo blkid -s TYPE -o value "$mounted_device")"
    [[ "$filesystem" == "xfs" ]] || fail "Expected XFS."

    data_uuid="$(sudo blkid -s UUID -o value "$mounted_device")"
    [[ -n "$data_uuid" ]] || fail "Filesystem UUID is missing."

    if awk '$1 !~ /^#/ && $2 == "/data" {found=1} END {exit !found}' /etc/fstab; then
        fail "/etc/fstab already contains /data; inspect that entry."
    fi

    fstab_backup="$(sudo mktemp /etc/fstab.before-orders.XXXXXX)"
    sudo cp -p /etc/fstab "$fstab_backup"
    printf 'fstab backup: %s\n' "$fstab_backup"

    printf '\nUUID=%s /data xfs defaults,nofail 0 2\n' "$data_uuid" |
        sudo tee -a /etc/fstab

    sudo systemctl daemon-reload
    sudo findmnt --verify --verbose
)
```

Record the backup filename. If validation reports errors, investigate and
correct the entry or restore the recorded backup before rebooting.

Test the entry while the application is still uninstalled.
Run each command separately and stop if it fails:

```bash
sudo umount /data
```

```bash
sudo mount /data
```

```bash
findmnt --mountpoint /data
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,SERIAL
```

Confirm the expected restored disk is mounted again at /data.
Using mount /data tests the entry in /etc/fstab.

## 5 Install and start the application

Use the extracted bundle directory and verified volume ID from the
previous steps:

```bash
sudo bash "$bundle_dir/recovery/install-application.sh" "$expected_volume"
```

The installer:

- Checks the Python source syntax.
- Verifies the mounted disk and existing database.
- Creates the matching application user and group if needed.
- Installs application code and the systemd service.
- Enables and starts orders-app.

It does not create or seed a database.

Check the service:

```bash
sudo systemctl status orders-app --no-pager
```

Allow a short startup interval when checking health:

```bash
curl --fail --silent --show-error \
  --retry 10 --retry-connrefused --retry-delay 1 \
  http://127.0.0.1:8080/health
```

Then complete the database-integrity and order checks in section 12
of recovery/runbook.md.

Do not declare recovery successful based only on service status.

## 6 Verify startup after reboot

After the mount, service and database checks pass, reboot only the
verified recovery server:

```bash
sudo reboot
```

The Systems Manager session will disconnect.
Reconnect to the same instance when it becomes available.

Run:

```bash
date -u
uptime -s
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,SERIAL
findmnt --mountpoint /data
sudo systemctl status orders-app --no-pager
curl --fail --silent --show-error http://127.0.0.1:8080/health
curl --fail --silent --show-error http://127.0.0.1:8080/orders
```

Verify that the correct disk mounted automatically, the application
started automatically, and the expected orders remain present.

Repeat the database-integrity check from the recovery runbook.
Record the verification time and evidence.

When measuring recovery from a fresh server, include its provisioning
and preparation time. Record application availability and reboot
verification separately if they finish at different times.

The earlier 8-minute-5-second result used an already-prepared server.
It is not a measured result for this fresh-server procedure.
