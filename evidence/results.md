# Recorded test results

This document summarises command outputs and observations recorded during
the lab on 12–14 October 2026. It is a historical evidence summary, not
a fresh check of the AWS environment.

Supporting implementation notes are in [myNotes.txt](../myNotes.txt).
Times below are UTC.

## Backup and alert verification

| Check | Recorded result |
|---|---|
| Controlled on-demand backup | Job d79d0d62-5caa-413c-8226-7c5c48ffa555 completed on 12 October |
| Controlled recovery point | snap-05ded9da1639af7ee; encrypted, seven-day retention |
| Scheduled backup | Job C2972602-ABB9-AB33-E927-692DC850F626 completed on 13 October |
| Scheduled recovery point | snap-09ee62769b9a9bc19; recorded creation time 03:00:00 |
| Cancellation alert | Job 505d0ea6-a6f9-400a-a3a9-787f8dfb4472 reached ABORTED; matching email received |
| Cancelled-job cleanup check | No recovery point remained in the vault; returned snapshot ID was not found in EBS |
| Event-pattern checks | Sample failure matched; completed job and unrelated vault did not match |

The ABORTED test verified the AWS Backup → EventBridge → SNS → email path.
A real FAILED job was not deliberately generated.

## Controlled deletion recovery — 13 October 2026

The original application received a post-backup marker before one specific
order, ORD-1002 (Keyboard), was deliberately deleted.

| Event | Time or identifier |
|---|---|
| Selected snapshot | snap-09ee62769b9a9bc19 |
| Post-backup marker created | 17:29:34 |
| Deletion incident recorded | 17:32:06.816269 |
| Restore job | 1b46a53b-8a82-471c-9809-8d276e9148dc |
| Restore request accepted | 17:32:58.708 |
| Restore job completed | 17:34:14.537 |
| New restored volume | vol-0c66915a87c30fcf7 |
| Recovered application verified | 17:40:12 |

Results:

- The deleted Keyboard order was recovered.
- All four baseline orders retained their values and timestamps.
- Post-backup marker ORD-F4F3785E89AE was absent.
- SQLite integrity checking returned ok.
- The restored database matched the four-order baseline SHA-256:

  4a9f446a0a0b2461917cae20c0392aa6079b93d0722da3290f8c07ead3737d01

Incident to application verification took approximately 8 minutes 5 seconds.

The selected recovery point's recorded creation time was approximately
14 hours 32 minutes before the incident. One known later write was not
recovered.

This exercise used an already-prepared recovery server. The timing excluded
server provisioning and real client traffic switching. It does not establish
a guaranteed RTO or an exact snapshot consistency timestamp.

## Original server unavailable — 13 October 2026

The original instance was manually stopped at 17:44:07.
At 17:44:56, the recovery application remained healthy with all four
recovered orders.

The 49-second interval was an observation interval, not a restore duration
or automatic-failover measurement.

## Fresh-server setup — 14 October 2026

Temporary instance: i-09f20d5907d3eb625.

Data volume: vol-0a5d57740e49daaad, an existing restored copy containing
the four baseline orders and recovery verification order ORD-D43D41B770CC.

Application bundle SHA-256:

052fd906ebd78924ecc76d609efb08ef10249598246da3475896c50d2582381f

Verified results:

- Windows and Linux archive checksums matched.
- Both shell scripts passed Bash syntax checks on Amazon Linux.
- The correct restored disk mounted through /etc/fstab.
- Preparation and installation scripts completed successfully.
- All five expected orders were returned by the application.
- SQLite integrity passed; verification time was 09:43:56.
- After reboot, mounting and application startup were automatic.
- All five orders retained their original values and timestamps.
- Post-reboot SQLite integrity passed at 09:46:46.

This test validated scripted preparation of a fresh server using an
existing restored disk. It did not include a new AWS Backup restore.

## Temporary test cleanup

Terraform removed the temporary instance and its volume attachment.

Follow-up checks confirmed:

- Restored volume vol-0a5d57740e49daaad was available with no attachments.
- Test root volume vol-0df8a214e16ed6b41 returned InvalidVolume.NotFound.
- Terraform subsequently reported no changes.

The main lab resources remained provisioned. This was not full teardown.

## Full project teardown, 14 October 2026

After the recovery tests, the backup assignment was removed and no unfinished
backup or restore jobs were found. All three recovery points were deleted.

Terraform then destroyed the remaining 27 managed resources. Verification
confirmed empty Terraform state and both main servers terminated.

Both restored data volumes were deleted. No project-tagged EBS volumes,
known backup snapshots or additional snapshots associated with the three
data disks remained.

The project Terraform role and its six unused policies were also removed.
Protected account and bootstrap resources were preserved.

Final billing review remains outstanding.