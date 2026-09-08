variable "project_name" {
  description = "Project name used for AWS resource names"
  type        = string
  default     = "bluegreen-cicd"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_a_cidr" {
  description = "CIDR block for public subnet A"
  type        = string
  default     = "10.20.1.0/24"
}

variable "public_subnet_b_cidr" {
  description = "CIDR block for public subnet B"
  type        = string
  default     = "10.20.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for BLUE and GREEN servers"
  type        = string
  default     = "t3.micro"
}