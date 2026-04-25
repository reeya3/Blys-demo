variable "name" {
  description = "Name prefix for secret resources"
  type        = string
}

variable "secret_path" {
  description = "Secrets Manager path/name for the application secret"
  type        = string
  default     = "blys/app/secret"
}
