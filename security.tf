resource "aws_security_group" "app" {
  name        = "backup-recovery-app"
  description = "Application server with outbound HTTPS and no inbound access."
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name    = "backup-recovery-app"
    Project = "backup-recovery"
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.app.id
  description       = "Outbound HTTPS for Systems Manager and software downloads."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = {
    Name    = "backup-recovery-https-egress"
    Project = "backup-recovery"
  }
}