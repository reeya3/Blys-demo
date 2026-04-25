## Cost Reduction
- Single NAT Gateway: ~$32/mo vs ~$64/mo for dual-NAT HA. Acceptable trade-off for PoC.
- Fargate (no idle EC2): only pay per task CPU/memory second.
- CloudWatch log retention set to 14 days.
- ECR lifecycle policy to purge old images.

## Disaster Recovery
1. Infrastructure is 100% in code — re-run terraform apply in a second region.
2. SSM parameter values must be seeded (via CI secret or manual) before apply.
3. ECR images must be replicated (ECR replication rules) or rebuilt via CI.
4. ALB DNS — update Route 53 or CNAME to new region endpoint.
5. RTO estimate: ~20 min (terraform apply) + image pull warmup.

## Observability
- CloudWatch Container Insights: CPU, memory, task count (already enabled in ecs.tf).
- CloudWatch Alarms: ALB 5xx rate, ECS CPU > 80%, task count < desired.
- Structured logging in server.js (use pino or winston for JSON logs).
- X-Ray tracing (add to ECS task definition for distributed tracing).
- Optional: Prometheus + Grafana on a separate ECS service for custom metrics.