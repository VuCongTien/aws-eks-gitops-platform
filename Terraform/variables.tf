variable "aws_region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS Region deploy resources"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for VPC"
}

variable "public_subnet_cidr_1a" {
  type        = string
  default     = "10.0.1.0/24"
  description = "CIDR cho Public Subnet"
}

variable "public_subnet_cidr_1b" {
  type        = string
  default     = "10.0.2.0/24"
  description = "CIDR cho Public Subnet"
}

variable "private_subnet_cidr_eks_1a" {
  type        = string
  default     = "10.0.3.0/24"
  description = "CIDR cho Private Subnet EKS"
}

variable "private_subnet_cidr_eks_1b" {
  type        = string
  default     = "10.0.4.0/24"
  description = "CIDR cho Private Subnet EKS"
}

variable "private_subnet_cidr_db_1a" {
  type        = string
  default     = "10.0.5.0/24"
  description = "CIDR cho Private Subnet DB"
}

variable "private_subnet_cidr_db_1b" {
  type        = string
  default     = "10.0.6.0/24"
  description = "CIDR cho Private Subnet DB"
}

variable "availability_zone_1a" {
  type        = string
  default     = "ap-southeast-1a"
  description = "Availability Zone để đặt subnet"
}

variable "availability_zone_1b" {
  type        = string
  default     = "ap-southeast-1b"
  description = "Availability Zone để đặt subnet"
}

variable "db_password" {
  type        = string
  default     = "Admin123456"
  description = "Password for PostgreSQL RDS"
}
