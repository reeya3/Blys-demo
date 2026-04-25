# Blys DevOps Challenge - Terraform PoC

## Overview
This project provisions a production-style AWS infrastructure using Terraform.

## Architecture
- VPC with public and private subnets across 2 AZs
- Internet-facing ALB
- ECS Fargate cluster in private subnets
- NAT Gateway for outbound traffic
- Secrets stored in AWS Secrets Manager
- IAM roles with least privilege

## Design Decisions
- ECS Fargate used for serverless container execution
- Private subnet isolation for security
- ALB as single entry point
- Single NAT Gateway for cost optimization (scalable to multi-AZ)

## How to Run

```bash
terraform init
terraform apply