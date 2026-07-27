output "ip_of_webapp" {
  description = "IP of webapp"
  # Берём значение публичного IP-адреса первого экземпляра
  # и выводим его по завершении работы Terraform
  value       = aws_eip.eips[0].public_ip
}