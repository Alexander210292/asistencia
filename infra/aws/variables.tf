variable "aws_region" {
  description = "AWS region where the academic demo will be deployed."
  type        = string
  default     = "us-east-1"
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