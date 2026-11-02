variable "aws_region" {
  description = "AWS region where the academic demo will be deployed."
  type        = string
  default     = "us-east-2"
}

variable "instance_type" {
  description = "Check eligibility and current cost in the AWS Billing console before applying."
  type        = string
  default     = "t3.micro"
}

variable "ssh_ingress_cidr" {
  description = "Your current public IPv4 address with /32, used to restrict SSH."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ssh_ingress_cidr))
    error_message = "ssh_ingress_cidr must be a valid CIDR, such as 203.0.113.10/32."
  }
}

variable "api_ingress_cidr" {
  description = "CIDR allowed to reach the API. Use 0.0.0.0/0 if students will connect from arbitrary networks."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrnetmask(var.api_ingress_cidr))
    error_message = "api_ingress_cidr must be a valid IPv4 CIDR."
  }
}

variable "repository_url" {
  description = "Public HTTPS Git repository cloned by cloud-init."
  type        = string
  default     = "https://github.com/Alexander210292/asistencia.git"

  validation {
    condition     = can(regex("^https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\\.git)?$", var.repository_url))
    error_message = "repository_url must be a public GitHub HTTPS repository URL without credentials."
  }
}

variable "repository_ref" {
  description = "Branch or tag checked out by cloud-init."
  type        = string
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]*$", var.repository_ref)) && !strcontains(var.repository_ref, "..") && !strcontains(var.repository_ref, "//")
    error_message = "repository_ref must be a branch or tag name without option prefixes, '..', or empty path segments."
  }
}

variable "db_password_parameter_name" {
  description = "Existing SSM SecureString parameter containing the MySQL application password."
  type        = string
  default     = "/uagrm-asistencia/academic-demo/db-password"

  validation {
    condition     = can(regex("^/[A-Za-z0-9_.\\-/]+$", var.db_password_parameter_name))
    error_message = "Use an absolute SSM parameter name containing only letters, numbers, '.', '_', '-', and '/'."
  }
}

variable "admin_password_parameter_name" {
  description = "Existing SSM SecureString parameter containing the initial administrator password."
  type        = string
  default     = "/uagrm-asistencia/academic-demo/admin-password"

  validation {
    condition     = can(regex("^/[A-Za-z0-9_.\\-/]+$", var.admin_password_parameter_name))
    error_message = "Use an absolute SSM parameter name containing only letters, numbers, '.', '_', '-', and '/'."
  }
}