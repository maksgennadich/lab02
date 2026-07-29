locals {
  vm_config = {
    "APP01"     = "ru-msk-comp1p"
    "APP02"     = "ru-msk-vol51"
    "APP03"     = "ru-msk-vol52"
    "Jumphost"  = "ru-msk-vol51"
    "HaProxy01" = "ru-msk-vol51"
    "MYSQL01"   = "ru-msk-comp1p"
    "MYSQL02"   = "ru-msk-vol51"
  }
}

data "vault_generic_secret" "cloud" {
  path = "lab2/cloud"
}

provider "vault" {
  address = "http://127.0.0.1:8200"
}

# Провайдер облака с ключами из Vault
provider "aws" {
  insecure   = false
  access_key = data.vault_generic_secret.cloud.data["access_key"]
  secret_key = data.vault_generic_secret.cloud.data["secret_key"]
  region     = "ru-msk"
}


resource "aws_key_pair" "pubkey" {
  # Указываем имя SSH-ключа (значение берётся из переменной pubkey_name)
  key_name   = var.pubkey_name
  # и содержимое публичного ключа
  public_key = data.vault_generic_secret.cloud.data["public_key"]
}

resource "aws_s3_bucket" "bucket" {
  # Задаём имя хранилища из переменной bucket_name
  bucket = var.bucket_name
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  # Указываем разрешения на доступ к созданному бакету
  bucket = aws_s3_bucket.bucket.id
  acl    = "private"
}
resource "aws_eip" "eips" {
  count = var.eips_count
  vpc = true

  tags = {
    Name = "${var.hostnames[count.index]}"
  }
}

resource "aws_security_group" "ext" {
  vpc_id = aws_vpc.vpc.id
  name = "ext"
  description = "External SG"

  dynamic "ingress" {
    iterator = port
    for_each = var.allow_tcp_ports
    content {
      from_port = port.value
      to_port   = port.value
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "External SG"
  }
}

resource "aws_security_group" "int" {
  vpc_id      = aws_vpc.vpc.id
  name        = "int"
  description = "Internal SG"

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Internal SG"
  }
}

resource "aws_security_group" "db" {
  vpc_id      = aws_vpc.vpc.id
  name        = "db-sg"
  description = "Security Group for Database nodes"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.int.id] # Доступ только для членов группы "int"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Database SG"
  }
}

resource "aws_instance" "vms" {
  for_each = local.vm_config

  ami           = var.vm_template
  instance_type = var.vm_instance_type
  
  subnet_id = (
    each.key == "Jumphost"
    ? aws_subnet.public.id
    : aws_subnet.private[each.value].id
  ) 
  source_dest_check = each.key == "Jumphost" ? false : true

  vpc_security_group_ids = (
    each.key == "Jumphost" || length(regexall("NLB", each.key)) > 0 
    ? [aws_security_group.ext.id, aws_security_group.int.id] 
    : (length(regexall("MYSQL", each.key)) > 0 
        ? [aws_security_group.db.id, aws_security_group.int.id] 
        : [aws_security_group.int.id])
  )

  key_name = aws_key_pair.pubkey.key_name

  tags = {
    Name = "VM for ${each.key}"
  }

  user_data = <<-EOF
    #!/bin/bash
    HOSTNAME="${each.key}"
    hostnamectl set-hostname $HOSTNAME
    echo "$HOSTNAME" > /etc/hostname
    yum update -y

    if [[ "$HOSTNAME" == *"MYSQL"* || "$HOSTNAME" == *"ELK"* ]]; then
        DISK=$(lsblk -dno NAME,SIZE | grep "32G" | awk '{print "/dev/"$1}' | head -n 1)
        if [ -n "$DISK" ]; then
            pvcreate $DISK
            vgcreate vg_data $DISK
            lvcreate -l 100%FREE -n lv_data vg_data
            mkfs.xfs /dev/vg_data/lv_data
            
            if [[ "$HOSTNAME" == *"MYSQL"* ]]; then
                MOUNT_POINT="/var/lib/mysql"
                grep -q "mysql" /etc/passwd || useradd -r -s /sbin/nologin mysql
            elif [[ "$HOSTNAME" == *"ELK"* ]]; then
                MOUNT_POINT="/var/lib/elasticsearch"
                grep -q "elasticsearch" /etc/passwd || useradd -r -s /sbin/nologin elasticsearch
            fi
            
            mkdir -p $MOUNT_POINT
            echo "/dev/mapper/vg_data-lv_data $MOUNT_POINT xfs defaults 0 0" >> /etc/fstab
            mount -a
            chown -R $(basename $MOUNT_POINT | sed 's/elasticsearch//;s/mysql//') $MOUNT_POINT # Упрощенно
            # Лучше оставить явные chown как в прошлом сообщении
        fi
    fi
    systemctl enable sshd
    systemctl start sshd
EOF
}


resource "aws_security_group" "jumphost" {
  vpc_id      = aws_vpc.vpc.id
  name        = "jumphost-sg"
  description = "Jumphost + NAT"
  

  # SSH только FortiVPN
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.fortivpn_cidrs
  }

  # Разрешаем трафик из VPC к Jumphost (для NAT форвардинга)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Jumphost SG" }
}

resource "aws_eip_association" "jumphost_eip_association" {
  depends_on = [aws_internet_gateway.igw]

  instance_id   = aws_instance.vms["Jumphost"].id
  allocation_id = aws_eip.eips[0].id
}