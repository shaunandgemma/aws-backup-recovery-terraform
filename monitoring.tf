resource "aws_sns_topic" "backup_alerts" {
  name = "backup-recovery-alerts"

  tags = {
    Name    = "backup-recovery-alerts"
    Project = "backup-recovery"
  }
}

resource "aws_sns_topic_subscription" "backup_email" {
  topic_arn = aws_sns_topic.backup_alerts.arn
  protocol  = "email"
  endpoint  = var.backup_alert_email
}

resource "aws_cloudwatch_event_rule" "backup_failure" {
  name        = "backup-recovery-job-failures"
  description = "Detect unsuccessful backup jobs in the project vault."

  event_pattern = jsonencode({
    source        = ["aws.backup"]
    "detail-type" = ["Backup Job State Change"]

    detail = {
      backupVaultArn = [aws_backup_vault.lab.arn]
      state          = ["FAILED", "EXPIRED", "ABORTED"]
    }
  })

  tags = {
    Name    = "backup-recovery-job-failures"
    Project = "backup-recovery"
  }
}

resource "aws_sns_topic_policy" "backup_alerts" {
  arn = aws_sns_topic.backup_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowEventBridgeToPublish"
        Effect = "Allow"

        Principal = {
          Service = "events.amazonaws.com"
        }

        Action   = "sns:Publish"
        Resource = aws_sns_topic.backup_alerts.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "backup_alerts" {
  rule           = aws_cloudwatch_event_rule.backup_failure.name
  event_bus_name = aws_cloudwatch_event_rule.backup_failure.event_bus_name
  target_id      = "SendBackupFailuresToSns"
  arn            = aws_sns_topic.backup_alerts.arn

  depends_on = [
    aws_sns_topic_policy.backup_alerts
  ]
}

