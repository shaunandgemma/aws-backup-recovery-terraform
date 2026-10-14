resource "aws_iam_role" "app" {
  name        = "backup-recovery-ec2-role"
  description = "Allows the application EC2 instance to use Systems Manager."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "backup-recovery-ec2-role"
    Project = "backup-recovery"
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "backup-recovery-ec2"
  role = aws_iam_role.app.name

  tags = {
    Name    = "backup-recovery-ec2"
    Project = "backup-recovery"
  }
}

resource "aws_iam_role" "backup" {
  name        = "backup-recovery-backup-role"
  description = "Allows AWS Backup to perform backups for the recovery lab."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "backup-recovery-backup-role"
    Project = "backup-recovery"
  }
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role" "restore" {
  name        = "backup-recovery-restore-role"
  description = "Allows AWS Backup to restore resources for the recovery lab."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "backup-recovery-restore-role"
    Project = "backup-recovery"
  }
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.restore.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

