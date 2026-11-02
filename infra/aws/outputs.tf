output "frontend_url" {
  description = "Open this URL after deploying the frontend process."
  value       = "http://${aws_instance.frontend.public_ip}:8080"
}

output "backend_api_url" {
  description = "Set this as API_BASE_URL in the frontend configuration."
  value       = "http://${aws_instance.backend.public_ip}:3000"
}

output "frontend_ssh" {
  description = "SSH command for the frontend EC2 instance."
  value       = "ssh -i \"${local_sensitive_file.ssh_private_key.filename}\" ubuntu@${aws_instance.frontend.public_ip}"
}

output "backend_ssh" {
  description = "SSH command for the backend EC2 instance."
  value       = "ssh -i \"${local_sensitive_file.ssh_private_key.filename}\" ubuntu@${aws_instance.backend.public_ip}"
}

output "ssh_private_key_path" {
  description = "Local path of the generated SSH private key. Protect this file and do not commit it."
  value       = local_sensitive_file.ssh_private_key.filename
}

output "backend_private_ip" {
  description = "Private address of the backend instance within the VPC."
  value       = aws_instance.backend.private_ip
}