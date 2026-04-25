variable "name" {
  description = "Name prefix for compute resources (e.g. 'blys-app')"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch logs configuration"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "ecs_sg_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the ECS task execution IAM role"
  type        = string
}

variable "app_secret_arn" {
  description = "ARN of the Secrets Manager secret for APP_SECRET"
  type        = string
}

variable "container_image" {
  description = "Full container image URI (e.g. public.ecr.aws/blys/blys-app:v1.0.0)"
  type        = string
}

variable "app_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path for ALB health checks"
  type        = string
  default     = "/health"
}

variable "task_cpu" {
  description = "Fargate task CPU units"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate task memory (MiB)"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Initial desired ECS task count"
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

variable "cpu_scale_target" {
  description = "Target CPU utilization (%) for auto-scaling"
  type        = number
  default     = 60.0
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "node_env" {
  description = "NODE_ENV environment variable value"
  type        = string
  default     = "production"
}
