resource "aws_vpc" "lab" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "backup-recovery-vpc"
    Project = "backup-recovery"
  }
}

resource "aws_subnet" "app" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = false

  tags = {
    Name    = "backup-recovery-app-subnet"
    Project = "backup-recovery"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name    = "backup-recovery-igw"
    Project = "backup-recovery"
  }
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name    = "backup-recovery-app-routes"
    Project = "backup-recovery"
  }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.app.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}

resource "aws_route_table_association" "app" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.app.id
}