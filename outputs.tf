output "ip_of_webapp" {
  description = "IP of webapp"
  value       = aws_eip.eips[0].public_ip
}
