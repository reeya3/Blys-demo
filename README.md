# Blys Demo — Implementation of ECS (Fargate) on AWS and its CI/CD Pipeline

Terraform infrastructure and CI/CD pipeline for the Blys containerised microservice, built as a response to the Blys DevOps Challenge.

---

## Table of Contents

- [Repository Structure](#repository-structure)
- [Challenge Coverage](#challenge-coverage)
- [Prerequisites](#prerequisites)
- [CI/CD Pipeline](#cicd-pipeline)
- [First-Time Setup](#first-time-setup)
- [Deploying](#deploying)
- [Adding a New Environment](#adding-a-new-environment)
- [Runbook — 3 AM Troubleshooting](#runbook--3-am-troubleshooting)
- [Known Trade-offs](#known-trade-offs)

---

## Repository Structure

```
├── .github/
│   └── workflows/
│       └── deploy.yml                 # CI/CD: lint → build → scan → push → deploy
├── blys-demo-app
    └── src
        └── server.js
    |── Dockerfile
    |── package.json
    |── package-lock.json
blys-tf/
├── versions.tf                        # Provider + Terraform version pins; remote backend stub             
├── modules/
│   ├── networking/                    # VPC, subnets (public + private), IGW, NAT, route tables
│   ├── security/                      # Security groups (ALB, ECS) — least-privilege ingress
│   ├── iam/                           # ECS task execution role with scoped policy
│   ├── secrets/                       # AWS Secrets Manager secret (shell; value set manually)
│   └── compute/                       # ALB, ECS cluster/task/service, auto-scaling, CloudWatch logs
└── environments/
    └── prod/
        ├── main.tf                    # Wires all modules together for production
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars
├── README.md
├── REASONING.md
└── .gitignore

```

---

## Challenge Coverage

| Requirement            | Implementation                    |
| ---------------------- | --------------------------------- |
| Multi-AZ VPC           | 2 public + 2 private subnets      |
| ECS Fargate            | Containerized deployment          |
| ALB                    | HTTP (port 80) with health checks |
| Security Groups        | Least privilege access model      |
| Secrets Management     | AWS Secrets Manager integration   |
| IAM Security           | Scoped execution roles            |
| Auto Scaling           | CPU-based (2–4 tasks)             |
| CI/CD                  | GitHub Actions pipeline           |
| Security Scanning      | Trivy (HIGH/CRITICAL blocking)    |
| Infrastructure as Code | Terraform modular design          |
| Observability          | CloudWatch logs integration       |

---

## Prerequisites

| Tool | Minimum version |
|---|---|
| Terraform | 1.5.0 |
| AWS CLI | 2.x |
| Docker | 24.x |
| AWS account with a role you can assume locally | — |

---
## CI/CD Pipeline
This project uses a separated CI/CD approach to ensure clean responsibilities between build and deployment stages.

### CI Pipeline (Build & Security)

Triggered on every push to the main branch.

Responsibilities:

- Checkout source code
- Lint Dockerfile (Hadolint)
- Build Docker image
- Tag image using Git commit SHA (github.sha)
- Security scan image using Trivy (blocks HIGH/CRITICAL vulnerabilities)
- Push image to Amazon ECR

Output:
```
ECR Image:
<account-id>.dkr.ecr.ap-south-1.amazonaws.com/blys-app:<git-sha>
```

### CD Pipeline (Deployment via Terraform)

After CI succeeds:

Responsibilities:

- Receive the new image URI from CI
- Run terraform apply
- Update ECS task definition with the new image
- Trigger ECS rolling deployment
- Wait for service stability

The pipeline runs three jobs in sequence:

```
lint ──► build-scan-push ──► deploy
         (main only)         (main only)
```

| Job | Triggers | What it does |
|---|---|---|
| `lint` | All pushes and PRs | Hadolint on Dockerfile, `terraform fmt` check |
| `build-scan-push` | Push to `main` only | Builds image, Trivy scan (blocks on HIGH/CRITICAL), pushes SHA + latest tags to ECR |
| `deploy` | Push to `main` only, after clean scan | Rolling ECS update with immutable SHA image, waits for stability, Slack alert on failure |

**Required GitHub secrets:**

| Secret | Description |
|---|---|
| `AWS_ROLE_ARN` | ARN of the IAM role assumed via OIDC |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook for failure alerts (optional) |

**Image tagging:** Every image gets a `<git-sha>` tag (immutable, used for deployment).

---

## First-Time Setup

### 1. Create the ECR repository (once)

```bash
aws ecr create-repository \
  --repository-name blys-app \
  --region ap-south-1 \
  --image-scanning-configuration scanOnPush=true
```

### 2. Configure GitHub Actions OIDC trust

Create an IAM role that trusts `token.actions.githubusercontent.com` and store its ARN as a repository secret named `AWS_ROLE_ARN`. See [GitHub's OIDC documentation](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services).

### 3. Set the secret value

Terraform creates the Secrets Manager secret shell but does not write the value (plaintext must not enter Terraform state). Set it manually after `terraform apply`:

```bash
aws secretsmanager put-secret-value \
  --secret-id blys/app/secret \
  --secret-string '{"APP_SECRET":"your-value-here"}'
```

### 4. Bootstrap remote state (once, manually)
*** This step is ONLY required if you want to use S3 as Terraform remote state backend. ***

```bash
aws s3api create-bucket \
  --bucket blys-terraform-state \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

aws s3api put-bucket-versioning \
  --bucket blys-terraform-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket blys-terraform-state \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name blys-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1
```

Then uncomment the `backend "s3"` block in `versions.tf`.

---

## Deploying

```bash
cd environments/prod
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

After apply, the ALB DNS is printed:

```
Outputs:
  alb_dns = "blys-app-alb-123456789.ap-south-1.elb.amazonaws.com"
```

---

## Adding a New Environment

```bash
cp -r environments/prod environments/staging
# Update environments/staging/terraform.tfvars with staging values
cd environments/staging
terraform init
terraform apply
```

No module code changes are needed — all configuration is driven by variables.

---

## Runbook — 3 AM Troubleshooting

> This section is written for someone who has just been paged and has never touched this codebase before.
> Start at the top — work through each section in order until you find the problem.

---

### How traffic flows (read this first)

```
User browser
     │  HTTP request
     ▼
Application Load Balancer          ← public subnets, AZ-1 + AZ-2
  blys-app-alb-***.ap-south-1.elb.amazonaws.com
     │  port 8080
     ▼
ECS Fargate Tasks (2 minimum)      ← private subnets, AZ-1 + AZ-2
  Cluster : blys-cluster
  Service : blys-app-service
     │
     ├──▶ Secrets Manager          reads APP_SECRET on startup
     ├──▶ CloudWatch Logs          writes all stdout/stderr
     └──▶ NAT Gateway              outbound internet only (AZ-1)
```

If a user reports the site is down, the problem is at one of these three layers:
1. The ALB is not reaching the tasks (502 error)
2. The tasks are not starting or are crashing
3. A recent deployment broke something

---

### Step 1 — Check what healthy looks like

Run this first. It tells you the current state of the service in one command:

```bash
aws ecs describe-services \
  --cluster blys-cluster \
  --services blys-app-service \
  --region ap-south-1 \
  --query 'services[0].{
      Status:status,
      Running:runningCount,
      Desired:desiredCount,
      Pending:pendingCount,
      Deployments:deployments[*].{
        Status:status,
        Running:runningCount,
        Desired:desiredCount
      }
    }'
```

**What a healthy response looks like:**
```json
{
  "Status": "ACTIVE",
  "Running": 2,
  "Desired": 2,
  "Pending": 0,
  "Deployments": [
    { "Status": "PRIMARY", "Running": 2, "Desired": 2 }
  ]
}
```

If `Running` is less than `Desired`, or you see two deployments (PRIMARY + ACTIVE), something is wrong. Continue below.

---

### Scenario A — Tasks are not starting

**Symptoms:** `Running` count is 0 or less than `Desired`. Users getting 502 or 503.

```bash
# Step 1: See why ECS stopped trying
aws ecs describe-services \
  --cluster blys-cluster \
  --services blys-app-service \
  --region ap-south-1 \
  --query 'services[0].events[:5]'

# Step 2: Find the stopped task
aws ecs list-tasks \
  --cluster blys-cluster \
  --desired-status STOPPED \
  --region ap-south-1

# Step 3: Get the exact failure reason (replace <task-arn> with output from above)
aws ecs describe-tasks \
  --cluster blys-cluster \
  --tasks <task-arn> \
  --region ap-south-1 \
  --query 'tasks[0].{StoppedReason:stoppedReason, Containers:containers[*].{Name:name,Reason:reason,ExitCode:exitCode}}'
```

**Common causes and fixes:**

| Error message | Cause | Fix |
|---|---|---|
| `CannotPullContainerError` | ECR image tag does not exist | Check the image tag in `terraform.tfvars`; verify it exists in ECR |
| `ResourceInitializationError: unable to pull secrets` | IAM role cannot read the secret | Verify `blys/app/secret` exists in Secrets Manager in `ap-south-1` |
| `Essential container exited` with exit code 1 | Application crashed on startup | Check CloudWatch logs (see Scenario B) |
| `Fargate resource unavailable` | AWS capacity issue in the AZ | Temporary; ECS will retry automatically |

---

### Scenario B — ALB returning 502 / tasks failing health checks

**Symptoms:** Tasks are running (`Running == Desired`) but the site returns 502. The ALB cannot reach the tasks.

```bash
# Step 1: Get the target group ARN
aws elbv2 describe-target-groups \
  --names blys-app-tg \
  --region ap-south-1 \
  --query 'TargetGroups[0].TargetGroupArn'

# Step 2: Check if tasks are passing health checks (replace <tg-arn>)
aws elbv2 describe-target-health \
  --target-group-arn <tg-arn> \
  --region ap-south-1 \
  --query 'TargetHealthDescriptions[*].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}'

# Step 3: Read the application logs (live tail)
aws logs tail /ecs/blys-cluster/blys-app \
  --follow \
  --region ap-south-1
```

**Common causes and fixes:**

| Target health state | Cause | Fix |
|---|---|---|
| `unhealthy: Health checks failed` | App not responding on `/health` with 200 | Check logs for startup errors; verify app listens on port 8080 |
| `unused: Target.InvalidState` | Task just started, still warming up | Wait 60 seconds and re-check |
| `draining` | Old deployment being replaced | Normal during a rollout; wait for it to complete |

---

### Scenario C — Deployment is stuck / rollback needed

**Symptoms:** A new deployment was triggered but has been running for more than 10 minutes without reaching steady state. The old version is still serving traffic but the new one is not coming up.

```bash
# Check both deployments
aws ecs describe-services \
  --cluster blys-cluster \
  --services blys-app-service \
  --region ap-south-1 \
  --query 'services[0].deployments[*].{
      Status:status,
      TaskDef:taskDefinition,
      Desired:desiredCount,
      Running:runningCount,
      Failed:failedTasks,
      CreatedAt:createdAt
    }'
```

If the new deployment (`PRIMARY`) has `Running: 0` and `Failed` is going up, the new image is broken.

**To roll back to the previous working image:**

```bash
# 1. Find the previous task definition revision
aws ecs list-task-definitions \
  --family-prefix blys-app \
  --sort DESC \
  --region ap-south-1 \
  --query 'taskDefinitionArns[:3]'

# 2. Force the service back to the previous revision (replace <previous-arn>)
aws ecs update-service \
  --cluster blys-cluster \
  --service blys-app-service \
  --task-definition <previous-arn> \
  --region ap-south-1

# 3. Wait for it to stabilise
aws ecs wait services-stable \
  --cluster blys-cluster \
  --services blys-app-service \
  --region ap-south-1
```

Then update `container_image` in `environments/prod/terraform.tfvars` to the previous working SHA so the next `terraform apply` does not undo your rollback.

---

### Scenario D — Terraform state lock is stuck

**Symptoms:** Running `terraform plan` or `terraform apply` immediately errors with `Error acquiring the state lock`.

This happens when a previous Terraform run was killed mid-way (CI job cancelled, laptop closed, etc.) and did not release its lock.

```bash
# Release the stuck lock
aws dynamodb delete-item \
  --table-name blys-terraform-locks \
  --key '{"LockID":{"S":"blys-terraform-state/prod/terraform.tfstate"}}' \
  --region ap-south-1
```

Only do this if you are certain no other `terraform apply` is currently running.

---

## Known Trade-offs

| Decision | Trade-off |
|---|---|
| Single NAT Gateway (~$40/mo) | AZ-2 private subnet loses outbound internet if AZ-1 fails. Add `aws_nat_gateway.nat_az2` and a second private route table to resolve. |
| HTTP only on ALB | No TLS. Add an ACM cert and HTTPS listener with HTTP→HTTPS redirect for production. |
| Secret value set out-of-band | Intentional — keeps plaintext out of Terraform state and CI logs. |
| Remote backend commented out | Uncomment the `backend "s3"` block in `versions.tf` before the first production apply. |
