resource "aws_instance" "recovery" {
  ami           = "ami-0e5df6fd7455a69b3"
  instance_type = "t3.small"

  subnet_id                   = aws_subnet.app.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.app.name

  monitoring = false

  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name    = "backup-recovery-recovery-root"
      Project = "backup-recovery"
    }
  }

  tags = {
    Name    = "backup-recovery-recovery-server"
    Project = "backup-recovery"
    Purpose = "restore-test"
  }

  lifecycle {
    # Stopped instances temporarily have no auto-assigned public IPv4 address.
    ignore_changes = [associate_public_ip_address]
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_vpc_security_group_egress_rule.https,
    aws_route.internet,
    aws_route_table_association.app
  ]
}

resource "aws_volume_attachment" "recovery_data" {
  device_name = "/dev/sdf"
  volume_id   = var.restored_data_volume_id
  instance_id = aws_instance.recovery.id

  stop_instance_before_detaching = true
}