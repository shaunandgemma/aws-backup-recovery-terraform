resource "aws_backup_vault" "lab" {
  name          = "backup-recovery-vault"
  force_destroy = false

  tags = {
    Name    = "backup-recovery-vault"
    Project = "backup-recovery"
  }
}

resource "aws_backup_plan" "lab" {
  name = "backup-recovery-daily"

  rule {
    rule_name                    = "daily-seven-day-retention"
    target_vault_name            = aws_backup_vault.lab.name
    schedule                     = "cron(0 3 * * ? *)"
    schedule_expression_timezone = "Etc/UTC"
    start_window                 = 60
    completion_window            = 120

    lifecycle {
      delete_after = 7
    }

    recovery_point_tags = {
      Project = "backup-recovery"
    }
  }

  tags = {
    Name    = "backup-recovery-daily"
    Project = "backup-recovery"
  }
}

resource "aws_backup_selection" "data" {
  name         = "backup-recovery-data"
  plan_id      = aws_backup_plan.lab.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [
    aws_ebs_volume.data.arn
  ]

  depends_on = [
    aws_iam_role_policy_attachment.backup
  ]
}

