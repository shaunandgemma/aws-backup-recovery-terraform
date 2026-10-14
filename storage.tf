resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.app.availability_zone
  type              = "gp3"
  size              = 8
  encrypted         = true

  tags = {
    Name    = "backup-recovery-data"
    Project = "backup-recovery"
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.app.id

  stop_instance_before_detaching = true
}