# REASONING.md — Architectural Decisions

This document addresses the three business requirements from the Blys DevOps Challenge: cost reduction, disaster recovery, and observability. It also covers the key security and CI/CD decisions made along the way.

---

## 1. Cost Reduction

### NAT Gateway strategy

The most significant ongoing cost lever in this architecture is the NAT Gateway. AWS charges ~$0.056/hr per gateway for Asia pacific (Mumbai) region. Running one NAT Gateway per AZ (the fully HA approach) costs roughly **$80/month** before data charges. Running a single NAT Gateway costs roughly **$40/month**.

**Decision: single NAT Gateway in AZ-1.**

For a PoC and early-stage production workload, the $40/month saving outweighs the risk. The failure scenario — AZ-1 goes down — would take out the NAT Gateway, meaning AZ-2 private tasks lose outbound internet. However, the ECS tasks themselves (being in private subnets across both AZs) would still serve traffic through the ALB as long as they do not need to make outbound calls. If outbound calls are critical, the upgrade path is straightforward: add a second `aws_nat_gateway` resource in `modules/networking/main.tf` and a second private route table for AZ-2. The code is already structured to make this a small diff.

### Fargate sizing

The task is provisioned at 256 CPU units (0.25 vCPU) and 512 MB memory — the smallest Fargate configuration. This is appropriate for a "Hello World" container. In production, right-sizing via CloudWatch Container Insights metrics (CPU/memory utilisation over time) is the recommended approach before committing to a larger task size.

### Auto-scaling over over-provisioning

Rather than running a fixed fleet of 4 tasks, the service scales between 2 and 4 tasks with a CPU target of 60%. At quiet periods this saves approximately 50% of the compute cost versus a static count of 4.

### ECR image lifecycle

Not yet implemented, but recommended: an ECR lifecycle policy to expire untagged images older than 14 days and keep only the last 10 tagged images. This prevents unbounded storage growth.

```hcl
# Add to modules/compute/main.tf
resource "aws_ecr_lifecycle_policy" "blys_app" {
  repository = var.ecr_repo_name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      }
    ]
  })
}
```

### CloudWatch log retention

Logs are retained for 14 days (`retention_in_days = 14`). Indefinite retention is the default if not set, which can accumulate significant cost on a busy service. 14 days covers most post-incident investigations; adjust upward only if compliance requires it.

---

## 2. Disaster Recovery

### Current state: single-region

This PoC deploys to a single AWS region (`ap-south-1`). There is no active-active or active-passive cross-region setup. The following is the recovery procedure if `ap-south-1` becomes unavailable.

### RTO / RPO expectations (single-region)

| Metric | Estimate |
|---|---|
| RTO (time to restore service) | 20–40 minutes |
| RPO (data loss window) | Application is stateless — zero data loss for the service itself. Any database (not in scope here) would determine true RPO. |

### Step-by-step regional failover

1. **Choose a target region** (e.g., `ap-southeast-1` — Singapore — is the closest low-latency alternative to Mumbai).

2. **Bootstrap state infrastructure in the new region:**
   ```bash
   # Create a second state bucket and lock table in the new region
   aws s3api create-bucket --bucket blys-terraform-state-dr \
     --region ap-southeast-1 \
     --create-bucket-configuration LocationConstraint=ap-southeast-1
   aws dynamodb create-table --table-name blys-terraform-locks \
     --region ap-southeast-1 ...
   ```

3. **Create the ECR repository in the new region:**
   ```bash
   aws ecr create-repository --repository-name blys-app --region ap-southeast-1
   ```

4. **Replicate the container image:**
   The image is tagged with the git SHA. Pull it from the failed region's ECR (if accessible) or rebuild it from the git commit:
   ```bash
   git checkout <sha>
   docker build -t <new-ecr-uri>/blys-app:<sha> .
   docker push <new-ecr-uri>/blys-app:<sha>
   ```

5. **Deploy infrastructure in the new region:**
   ```bash
   cp -r environments/prod environments/dr
   # Update terraform.tfvars: aws_region = "ap-southeast-1"
   cd environments/dr
   terraform init -backend-config="bucket=blys-terraform-state-dr" \
                  -backend-config="region=ap-southeast-1"
   terraform apply
   ```

6. **Update DNS** to point to the new ALB DNS name (Route 53 record update or CNAME swap).

7. **Set the secret value** in the new region's Secrets Manager:
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id blys/app/secret \
     --region ap-southeast-1 \
     --secret-string '{"APP_SECRET":"..."}'
   ```

### What makes this fast

Because all infrastructure is code, steps 5–7 are deterministic and take roughly 10–15 minutes once the image is available. There is no manual console clicking. The modular structure means the DR environment is identical to production except for the region variable.

### What to do next to improve DR posture

- **Route 53 health checks + latency routing:** Automatically fail over DNS to a warm standby region when the primary ALB becomes unhealthy.
- **ECR replication:** AWS ECR supports cross-region replication. Enable it on the primary repository so the DR region always has the latest image without a manual push step.
- **Secrets Manager replication:** AWS Secrets Manager supports cross-region secret replication. Enable it to remove step 7 from the failover procedure.
- **Terraform workspace or separate pipeline for DR:** Run `terraform plan` against the DR region on every deployment to keep it warm and detect drift.

---

## 3. Observability

### What is currently in place

**CloudWatch Logs** — all ECS task stdout/stderr is shipped to `/ecs/blys-cluster/blys-app` with a 14-day retention window. Container Insights is enabled on the cluster, providing CPU, memory, network, and storage metrics at the task and service level without any agent installation.

### What should be added for a production service

#### Metrics and alerting

**CloudWatch Alarms** on the following signals, wired to an SNS topic (→ PagerDuty / Slack):

| Signal | Threshold | Why |
|---|---|---|
| `TargetResponseTime` (ALB) | p99 > 2s for 5 minutes | Latency degradation before users notice |
| `HTTPCode_Target_5XX_Count` | > 10 in 5 minutes | Application errors |
| `UnHealthyHostCount` | > 0 for 2 minutes | Tasks failing health checks |
| `CPUUtilization` (ECS service) | > 80% for 10 minutes | Scaling not keeping up |
| `MemoryUtilization` (ECS service) | > 85% for 10 minutes | Risk of OOM kills |

#### Distributed tracing

For a microservice that calls other services, **AWS X-Ray** (zero-config with Fargate) or **OpenTelemetry** (vendor-neutral, portable) provides request traces across service boundaries. This is the fastest path to answering "which downstream call is causing the latency spike?"

#### Log aggregation and search

For a small team, **CloudWatch Logs Insights** is sufficient — it supports SQL-like queries across log groups without additional infrastructure. Example query to find all 5xx errors in the last hour:

For a larger team or higher log volume, an **ELK stack (Elasticsearch + Logstash + Kibana)** or **Grafana + Loki** provides richer full-text search and dashboarding. Both can ingest from CloudWatch Logs via a subscription filter.

#### Synthetic monitoring

A **CloudWatch Synthetics canary** hitting the ALB `/health` endpoint every minute from outside the VPC detects availability issues that internal health checks miss (e.g., DNS problems, ALB misconfiguration). If the canary fails, the alarm fires before a real user is affected.

#### Recommended stack summary

| Layer | Tool | Rationale |
|---|---|---|
| Infrastructure metrics | CloudWatch + Container Insights | Zero setup for ECS Fargate; already enabled |
| Application logs | CloudWatch Logs | Co-located with infrastructure; no agent |
| Log search (scale) | CloudWatch Logs Insights → Loki/ELK | Start with Insights; migrate when query complexity grows |
| Tracing | AWS X-Ray or OpenTelemetry | Trace cross-service calls |
| Alerting | CloudWatch Alarms → SNS → PagerDuty | Proven, low-ops alert path |
| Synthetic checks | CloudWatch Synthetics | Outside-in availability monitoring |
| Dashboards | CloudWatch Dashboards → Grafana | Grafana when multi-source dashboards are needed |

---

## 4. Security Decisions

### OIDC over long-lived access keys

The CI/CD pipeline uses GitHub Actions OIDC to assume an IAM role rather than storing `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` as GitHub secrets. OIDC tokens are short-lived (scoped to a single workflow run) and cannot be leaked through secret scanning or log exposure.

### Least-privilege IAM policy

The ECS task execution role is scoped to exactly three resources:

- The specific CloudWatch log group ARN
- The specific ECR repository ARN
- The specific Secrets Manager secret ARN

It does not use `*` wildcards on any resource. If the task is compromised, the blast radius is limited to these three resources.

### Trivy scan blocks the push

Security scanning runs **before** the image is pushed to ECR. A HIGH or CRITICAL vulnerability causes the pipeline to exit with code 1, preventing the vulnerable image from ever reaching the registry or a running environment. SARIF results are uploaded to the GitHub Security tab so findings are visible to the team without requiring access to the CI logs.

### No HTTPS yet

The ALB currently only terminates HTTP on port 80. For production, an ACM certificate should be attached to an HTTPS listener (port 443) with an HTTP→HTTPS redirect rule on port 80. This was omitted from the PoC to avoid a dependency on a registered domain name.
