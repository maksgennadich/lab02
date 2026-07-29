locals {
  all_zones = ["ru-msk-comp1p", "ru-msk-vol51", "ru-msk-vol52"]

  # Публичную подсеть делаем в зоне ru-msk-vol51 (как у Jumphost)
  public_az = "ru-msk-vol51"
}

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true

  tags = {
    Name = "lab02"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "igw-${aws_vpc.vpc.tags["Name"]}"
  }
}

# ----------------------
# Public subnet (1)
# ----------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.public_az
  cidr_block              = "10.0.10.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-${local.public_az}"
    Tier = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "rt-public"
  }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private" {
  for_each          = toset(local.all_zones)
  vpc_id            = aws_vpc.vpc.id
  availability_zone = each.value

  # 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24
  cidr_block = "10.0.${index(local.all_zones, each.value) + 1}.0/24"

  tags = {
    Name = "private-${each.value}"
    Tier = "private"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "rt-private"
  }
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  instance_id            = aws_instance.vms["Jumphost"].id

  depends_on = [aws_instance.vms]
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# ----------------------
# Outputs (чтобы удобно было дальше)
# ----------------------
output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_ids" {
  value = { for k, s in aws_subnet.private : k => s.id }
}