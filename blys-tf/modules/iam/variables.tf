variable "name" {
  description = "Name prefix for IAM resources"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name the ECS role needs write access to"
  type        = string
}

variable "ecr_repo_name" {
  description = "ECR repository name the ECS role needs pull access to"
  type        = string
}

variable "secret_arn" {
  description = "ARN of the Secrets Manager secret the ECS task needs to read"
  type        = string
}
