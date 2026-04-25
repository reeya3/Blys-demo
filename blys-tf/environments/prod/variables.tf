variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "name" {
  description = "Project name used as a prefix for all resources"
  type        = string
  default     = "blys"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "app_port" {
  description = "Port the application container listens on"
  type        = number
  default     = 8080
}

variable "container_image" {
  description = "Full container image URI"
  type        = string
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum ECS task count for auto-scaling"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum ECS task count for auto-scaling"
  type        = number
  default     = 4
}
