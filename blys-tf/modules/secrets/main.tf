resource "aws_secretsmanager_secret" "app" {
  name = "${var.secret_path}"

  tags = {
    Name      = "${var.name}-app-secret"
    ManagedBy = "terraform"
  }
}
