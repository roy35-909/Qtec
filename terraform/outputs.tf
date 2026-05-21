output "server_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.app.public_ip
}

output "server_dns" {
  description = "Public DNS of the EC2 instance"
  value       = aws_instance.app.public_dns
}

output "app_url" {
  description = "Application URL through Nginx"
  value       = "http://${aws_instance.app.public_ip}:8079"
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${aws_instance.app.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "http://${aws_instance.app.public_ip}:9099"
}

