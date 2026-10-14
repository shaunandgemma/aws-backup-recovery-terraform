# Backup recovery runbook

## Purpose

For a newly provisioned recovery server, first follow
[Prepare a fresh recovery server](fresh-server-setup.md).

This procedure assumes the recovery EC2 server is already prepared with
Python, the orders-app user, application code, the systemd service and
the /data mount configuration. It covers replacing that server's data
disk with a newly restored volume. Building a recovery server from
scratch requires additional setup.

Recover the orders application from an AWS Backup recovery point onto a separate EC2 server and EBS volume.

The backup contains the data disk, including the SQLite database. Application code and the systemd service must be installed separately from Git.

Recovery targets are no more than 24 hours of data loss and verified application recovery within 60 minutes. Record actual results for each exercise.

## Environment

- AWS account: Sandbox, 652656942006.
- Region: eu-west-2.
- Recovery Availability Zone: eu-west-2a.
- Project directory: E:\code\backup_and_recovery_project.
- Normal project CLI profile: backup-recovery.
- Administrative bootstrap profile: sandbox-bootstrap.
- Backup vault: backup-recovery-vault.
- Database path: /data/orders/orders.db.
- Application service: orders-app.service.
- Local application endpoint: http://127.0.0.1:8080.

## Checks before recovery

1. Verify the AWS account and CLI profile before making changes.
2. Identify the incident and record its UTC start time.
3. Select the latest suitable recovery point from before the unwanted change. A newer backup might already contain the deleted or damaged data.
4. Verify the recovery point's source volume, status, encryption and retention deadline.
5. Confirm restore metadata specifies the intended Availability Zone, volume size, type and encryption key.
6. Check that the caller can start the restore and pass the dedicated restore role. The current project policy permits one specific recovery-point ARN; update it deliberately when selecting another.
7. Preserve the original disk and identify exactly which server will receive the restored disk.
8. Obtain explicit approval before deleting records, stopping the original server or replacing an attachment during a failure exercise.

## Recovery safeguards

- Never format a restored disk.
- Confirm its volume ID using the disk serial before mounting it.
- Do not run init_db.py against recovered data.
- Verify the restored volume and recovery server are in the same Availability Zone.
- Review the Terraform plan before applying. An attachment change should not replace an EC2 server.
- Record every restored volume ID. AWS Backup-created volumes are outside this project's Terraform state and require separate cleanup.
- Keep real variable values and credentials out of Git.

## Evidence required

- Selected recovery point, restore-job ID and restored volume ID.
- Incident start and application-verification times in UTC.
- Correct mounted disk and running application service.
- SQLite integrity result and expected order IDs, values and timestamps.
- Checksum comparison where an appropriate unchanged baseline exists.
- Records missing because they were written after the selected backup.
- Timing boundaries, including whether server provisioning and client traffic switching were included.

## 1 Verify the account

Run in Windows PowerShell from the project directory:

```powershell
$env:AWS_PROFILE = "backup-recovery"

aws sts get-caller-identity `
  --profile backup-recovery `
  --output json
```

Stop unless the account is 652656942006 and the ARN identifies the assumed aws-backup-recovery-terraform-role.

## 2 Select and inspect the recovery point

List the recovery points in the project vault:

```powershell
aws backup list-recovery-points-by-backup-vault `
  --backup-vault-name backup-recovery-vault `
  --profile backup-recovery `
  --region eu-west-2 `
  --query "sort_by(RecoveryPoints, &CreationDate)[].{Created:CreationDate,Status:Status,Source:ResourceArn,RecoveryPoint:RecoveryPointArn}" `
  --output json
```

The list is ordered oldest first. Select the latest suitable point from before the incident, checking the source volume as well as its date.

Assign its exact ARN to a PowerShell variable:

```powershell
$selectedRecoveryPointArn = "<paste-selected-recovery-point-ARN>"
```

Replace the placeholder before continuing. Keep this PowerShell session open because subsequent commands use the variable.

Inspect the selected point using the bootstrap profile, which has the required read permissions:

```powershell
aws backup describe-recovery-point `
  --backup-vault-name backup-recovery-vault `
  --recovery-point-arn $selectedRecoveryPointArn `
  --profile sandbox-bootstrap `
  --region eu-west-2 `
  --query "{Status:Status,Message:StatusMessage,SourceVolume:ResourceArn,Encrypted:IsEncrypted,EncryptionKey:EncryptionKeyArn,Created:CreationDate,RetentionDays:Lifecycle.DeleteAfterDays,DeleteAt:CalculatedLifecycle.DeleteAt}" `
  --output json
```

Record the output with the incident evidence. Investigate any incomplete status, unexpected source, encryption setting or expiry before proceeding.

Check that RestoreSelectedRecoveryPoint in the published bootstrap policy authorises this exact ARN. Editing the local JSON alone does not change AWS permissions.

## 3 Prepare the restore settings

Run in the same Windows PowerShell session:

```powershell
aws backup get-recovery-point-restore-metadata `
  --backup-vault-name backup-recovery-vault `
  --recovery-point-arn $selectedRecoveryPointArn `
  --profile sandbox-bootstrap `
  --region eu-west-2 `
  --output json
```

Compare the returned settings with recovery/ebs-restore-metadata.json.

For our existing lab, the file contains:

```json
{
  "availabilityZone": "eu-west-2a",
  "volumeType": "gp3",
  "volumeSize": "8",
  "encrypted": "true",
  "kmsKeyId": "arn:aws:kms:eu-west-2:652656942006:key/1ef1b7c6-5ab7-4740-bc5f-b60ca95e1da8"
}
```

Verify these values for the selected recovery point before using them.
The restored disk must be in the recovery server's Availability Zone.
All metadata values are strings, including size and encryption.

## 4 Start and monitor the restore

Create a unique token once for this restore attempt:

```powershell
$restoreToken = [guid]::NewGuid().ToString()
$restoreToken
```

Record the token. If retrying an uncertain request, reuse the same token
and parameters rather than generating a new token.

Start the restore:

```powershell
aws backup start-restore-job `
  --recovery-point-arn $selectedRecoveryPointArn `
  --metadata file://recovery/ebs-restore-metadata.json `
  --iam-role-arn arn:aws:iam::652656942006:role/backup-recovery-restore-role `
  --resource-type EBS `
  --idempotency-token $restoreToken `
  --profile backup-recovery `
  --region eu-west-2 `
  --output json
```

Record the returned RestoreJobId and assign it below:

```powershell
$restoreJobId = "<paste-returned-restore-job-ID>"
```

Check progress:

```powershell
aws backup describe-restore-job `
  --restore-job-id $restoreJobId `
  --profile backup-recovery `
  --region eu-west-2 `
  --query "{Status:Status,Message:StatusMessage,Created:CreationDate,Completed:CompletionDate,RestoredResource:CreatedResourceArn}" `
  --output json
```

Repeat the status check until the job completes or fails.
If it fails, investigate the message before starting another job.

On completion, record the new volume ID from RestoredResource.
AWS Backup has created a separate disk; it has not attached it to EC2
or verified that the application can use the restored database.

A COMPLETED restore job is not yet proof of successful application recovery.

## 5 Verify the restored volume

In the same Windows PowerShell session, set the volume ID returned
by the completed restore job:

```powershell
$restoredVolumeId = "<paste-new-restored-volume-ID>"
```

Inspect that specific disk:

```powershell
aws ec2 describe-volumes `
  --volume-ids $restoredVolumeId `
  --profile backup-recovery `
  --region eu-west-2 `
  --query "Volumes[].{VolumeId:VolumeId,State:State,AZ:AvailabilityZone,SizeGiB:Size,Type:VolumeType,Encrypted:Encrypted,KmsKeyId:KmsKeyId,SourceSnapshot:SnapshotId,Attachments:Attachments,Tags:Tags}" `
  --output json
```

Before attaching it, verify:

- VolumeId matches the completed restore job.
- State is available and Attachments is empty.
- AZ is eu-west-2a, matching the recovery server.
- SizeGiB is 8 and Type is gp3.
- Encrypted is true and KmsKeyId matches the intended key.
- SourceSnapshot matches the snapshot in the selected recovery-point ARN.

Stop and investigate any mismatch. Do not substitute the original data
volume or an older restored disk.

## 6 Tag the restored volume

Use the bootstrap profile to tag the verified disk. The project role's
tagging permissions require an existing Project tag, which a newly
restored volume might not have.

```powershell
aws ec2 create-tags `
  --resources $restoredVolumeId `
  --tags `
    Key=Name,Value=backup-recovery-restored-data `
    Key=Project,Value=backup-recovery `
    Key=Purpose,Value=restore-test `
  --profile sandbox-bootstrap `
  --region eu-west-2
```

A successful tagging command normally returns no output. Verify the tags:

```powershell
aws ec2 describe-volumes `
  --volume-ids $restoredVolumeId `
  --profile backup-recovery `
  --region eu-west-2 `
  --query "Volumes[0].Tags" `
  --output table
```

Record the volume ID, source snapshot and restore-job ID together.

Tags identify the disk but do not add it to Terraform state.
This project manages its attachment through Terraform; the restored
volume itself requires separate tracking and eventual cleanup.

## 7 Update the volume variable and review the plan

This procedure assumes the recovery server already exists and is configured
to mount /data and run orders-app.

In terraform.tfvars, replace only restored_data_volume_id with the new
volume ID verified in step 5:

```hcl
restored_data_volume_id = "<paste-new-restored-volume-ID>"
```

Keep the existing email setting. Do not commit terraform.tfvars to Git.

The attachment in recovery.tf already references this variable:

```hcl
volume_id = var.restored_data_volume_id
```

Run these commands individually in Windows PowerShell from the project
directory. Stop if any command fails:

```powershell
terraform fmt
```

```powershell
terraform validate
```

```powershell
terraform plan
```

For a new disk replacing the recovery server's current data disk, expect:

- aws_volume_attachment.recovery_data must be replaced.
- Its old volume_id changes to the verified new volume ID.
- The recovery instance ID remains unchanged.
- Plan: 1 to add, 0 to change, 1 to destroy.
- No other infrastructure changes.

Here, destroying the attachment means disconnecting the old disk.
It does not delete either restored volume.

Record the old and new volume IDs before proceeding. The old disk remains
available for investigation or rollback and continues to incur storage charges.

Stop if the plan replaces either EC2 instance, changes the original data
disk, deletes a volume or proposes unrelated changes.

If Terraform reports no changes, check whether the selected volume is
already attached. Do not force a replacement just to repeat the procedure.

Planning does not change infrastructure. Do not apply until the attachment
change has been reviewed and the recovery application is ready to stop.

## 8 Prepare the recovery server for the disk change

These steps apply to the existing recovery server, not the original server.

Confirm the recovery instance ID against Terraform and the EC2 console.
For the completed exercise, it was i-08bb3f3d7d4ef69b1.

Open a Systems Manager session to that recovery instance.

Before stopping anything, inspect the current disk:

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,SERIAL
findmnt --mountpoint /data
```

Match the mounted data disk's serial to the OLD volume ID recorded
during the plan review.

After approval for the attachment change, stop the recovery application:

```bash
sudo systemctl stop orders-app
systemctl is-active orders-app
```

Expected result: inactive.

Flush pending writes and unmount the data filesystem.
Run each command separately and stop if it fails:

```bash
sudo sync
```

```bash
sudo umount /data
```

Verify that /data is no longer mounted:

```bash
findmnt --mountpoint /data
```

No output is expected when the mount is absent.

If unmounting reports that the disk is busy, investigate the process
using it. Do not force-detach the volume.

## 9 Apply the reviewed attachment change

Return to Windows PowerShell in the project directory:

```powershell
terraform apply
```

Terraform generates a fresh plan. Review it again before entering yes.

For this disk swap, it must replace only
aws_volume_attachment.recovery_data, using the intended old and new
volume IDs and the same recovery instance.

Expected summary:

Plan: 1 to add, 0 to change, 1 to destroy.

The attachment has stop_instance_before_detaching = true.
Terraform stops the recovery server before detaching its old disk,
then attaches the new restored disk.

The Systems Manager session will disconnect when the server stops.

Wait for a successful apply. If it fails, inspect the actual instance
and volume attachment states before retrying.

Both data volumes are retained. Record the successful attachment change.
The next step is to check the attachment and start the recovery server.

## 10 Check the attachment and start the recovery server

In Windows PowerShell, set the recovery instance ID verified in step 8:

```powershell
$recoveryInstanceId = "<paste-verified-recovery-instance-ID>"
```

Check the newly restored volume:

```powershell
aws ec2 describe-volumes `
  --volume-ids $restoredVolumeId `
  --profile backup-recovery `
  --region eu-west-2 `
  --query "Volumes[].{VolumeId:VolumeId,State:State,Attachments:Attachments}" `
  --output json
```

Expected results:

- VolumeId is the newly restored disk.
- Volume state is in-use.
- Attachment state is attached.
- Attachment InstanceId matches $recoveryInstanceId.
- Attachment device is /dev/sdf.

Investigate any mismatch before starting the server.

Check the recovery server's state:

```powershell
aws ec2 describe-instances `
  --instance-ids $recoveryInstanceId `
  --profile backup-recovery `
  --region eu-west-2 `
  --query "Reservations[].Instances[].{InstanceId:InstanceId,State:State.Name,AZ:Placement.AvailabilityZone}" `
  --output table
```

If stopped, start that recovery instance:

```powershell
aws ec2 start-instances `
  --instance-ids $recoveryInstanceId `
  --profile backup-recovery `
  --region eu-west-2 `
  --output json
```

Wait for it to reach running:

```powershell
aws ec2 wait instance-running `
  --instance-ids $recoveryInstanceId `
  --profile backup-recovery `
  --region eu-west-2
```

The wait command normally returns no output on success.
If it fails, investigate before continuing.

Running does not prove that Systems Manager or the application is ready.
Wait until Session Manager allows a connection, then open a session
to this recovery instance.

## 11 Verify the restored filesystem and service

Run inside the recovery server's Systems Manager session:

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,SERIAL
findmnt --mountpoint /data
sudo systemctl status orders-app --no-pager
```

Verify that:

- The disk mounted at /data has the new restored volume's serial.
- Its filesystem is xfs.
- orders-app.service is active (running).

NVMe serials show the EBS volume ID without its hyphen.
Do not assume the data disk will always be named nvme1n1.

Our tested restores retained the original filesystem UUID.
The existing /etc/fstab entry therefore mounted the restored disk
automatically, and systemd started the application.

If /data is missing or points to the wrong disk, stop the application
and investigate before proceeding:

```bash
sudo systemctl stop orders-app
```

Never format the restored disk or initialise a replacement database.

If the correct disk is mounted but the service fails, inspect its logs:

```bash
sudo journalctl -u orders-app -n 50 --no-pager
```

A mounted disk and running service are intermediate checks.
Database integrity and application records must still be verified.

## 12 Verify database integrity and recovered orders

Run these checks inside the recovery server's Systems Manager session.
Do not add or change orders while comparing the restored data.

Check SQLite integrity using the application user and a read-only connection:

```bash
sudo -u orders-app python3 - <<'PY'
import os
import sqlite3

if not os.path.ismount("/data"):
    raise SystemExit("STOP: /data is not mounted.")

connection = sqlite3.connect(
    "file:/data/orders/orders.db?mode=ro",
    uri=True,
    timeout=5,
)
try:
    results = [
        row[0] for row in connection.execute("PRAGMA integrity_check")
    ]
    for result in results:
        print("Integrity:", result)
    if results != ["ok"]:
        raise SystemExit("STOP: database integrity check failed.")
finally:
    connection.close()
PY
```

Expected result: Integrity: ok.

Check the application:

```bash
curl --fail --silent --show-error http://127.0.0.1:8080/health
```

```bash
curl --fail --silent --show-error http://127.0.0.1:8080/orders
```

Compare the returned order IDs, products, quantities and timestamps with
the evidence for the selected backup. A correct count alone is insufficient.

For the 13 October deletion exercise, the expected recovered orders were:

- ORD-1001: Notebook, quantity 2.
- ORD-1002: Keyboard, quantity 1.
- ORD-1003: USB cable, quantity 3.
- ORD-8692B4044B9E: Monitor stand, quantity 1.

The post-backup marker ORD-F4F3785E89AE was correctly absent from that
recovery point. Its absence demonstrated an unrecovered later write.

For a different recovery point, use its own expected records.

Where an unchanged baseline file is available, compare its checksum:

```bash
sudo sha256sum /data/orders/orders.db
```

Our four-order baseline checksum was:

4a9f446a0a0b2461917cae20c0392aa6079b93d0722da3290f8c07ead3737d01

This checksum applies to that specific baseline, not every future backup.
A different checksum requires investigation; it does not automatically
mean corruption. Legitimate writes can change the database file.

## 13 Record recovery results and timing

After the required checks pass, record the verification time:

```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Save the actual outputs and record:

- Incident start time in UTC.
- Selected recovery point and its recorded creation time.
- Restore-job ID and new volume ID.
- Application-verification time in UTC.
- Integrity result and record comparison.
- Any expected records that could not be recovered.
- Whether server preparation and client traffic switching were included.

Calculate elapsed recovery time from incident start to successful
application verification. Compare it with the 60-minute RTO target.

Record the recovery point's age at the incident separately.
Its creation time is a useful approximation, not proof of the exact
last recoverable write. Compare recovered records with known later writes
when assessing data loss against the 24-hour RPO target.

Our completed deletion exercise demonstrated:

- Approximately 8 minutes 5 seconds to verified application recovery.
- A selected recovery point approximately 14 hours 32 minutes old.
- Recovery of the deleted Keyboard order.
- Loss of the post-backup marker from the recovered copy.
- Matching baseline checksum and a successful integrity check.

That exercise used an already-prepared recovery server.
It excluded server provisioning and real client traffic switching.
These results describe this test, not guaranteed future recovery times.

## 14 Handle failed checks

Do not declare recovery successful if the disk, database or application
checks fail.

If the restore job fails:

- Record its status message and job ID.
- Check restore metadata, IAM permissions and KMS access.
- Investigate before requesting another restore.
- Track any resources created by failed or repeated attempts.

If Terraform fails during the attachment change:

- Inspect the recovery instance state and both volume attachments.
- Run a fresh plan after understanding the failure.
- Do not assume the old disk is still attached.
- Do not force-detach a mounted disk.

If /data is missing or contains the wrong disk:

- Stop orders-app.
- Compare the attached volume ID with the Linux disk serial.
- Inspect the filesystem UUID and /etc/fstab entry.
- Never format the restored volume or run init_db.py.

If the correct disk is mounted but the application fails:

- Inspect systemd logs.
- Check that orders-app can access the database and its directory.
- Confirm that application code and the service definition are installed.
- Run the read-only SQLite integrity check.

If integrity fails or expected records are missing:

- Preserve the evidence and original resources.
- Check whether the selected backup predates the incident.
- Consider another suitable recovery point.
- Record any additional restore attempts and their volume IDs.

Reattaching a previous disk requires a reviewed attachment change.
It does not guarantee correct data: the original database in our deletion
exercise still contained the simulated deletion and post-backup marker.

## 15 Close the exercise and track cleanup

Record which server and volume contain the accepted recovered database.

The restored copy is independent of the original. It does not synchronise
with it, and this exercise did not switch real client traffic.

The existing backup selection protects the original data volume only.
A restored volume is not automatically added to that selection merely
because it has the Project tag. If the recovered copy becomes the ongoing
application, review and update its backup protection deliberately.

Before cleanup:

- Save recovery evidence and update myNotes.txt.
- Review and commit the intended configuration and documentation changes.
- Keep terraform.tfvars, credentials, state and saved plans out of Git.
- List the original, current recovery and detached restored volumes.
- Identify which resources must be retained and why.
- Obtain approval for the specific resources to delete.

Terraform manages the recovery instance and its volume attachment.
AWS Backup created the restored volumes outside Terraform state.
Removing an attachment does not delete its volume.

Detached restored volumes require separate cleanup.
Backup retention does not automatically delete restored EBS volumes.

Do not delete the accepted recovery copy, original evidence or remaining
usable recovery points while they are still needed.

Stopping an EC2 server does not remove its EBS storage charges.
Record the final instance states and remaining chargeable resources.

After any approved cleanup, verify the actual AWS resources remaining.
Protect John, the AWS Organization, member accounts and unrelated resources.

