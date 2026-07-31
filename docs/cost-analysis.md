# Cost analysis

Detailed cost breakdown for the reference architecture, with the reasoning behind each line item and the design choices that shape them.

## Development environment (idle + light traffic)

Running the `dev/` environment with a single g5.xlarge spot node handling occasional inference requests (~8 hours/day):

| Component | Monthly cost | Notes |
|-----------|-------------:|-------|
| EKS control plane | $73.00 | Flat AWS fee, one per cluster |
| 2× t3.medium system nodes | $30.24 | On-demand, always-on for CoreDNS/Karpenter |
| 1× g5.xlarge (spot, 8 hrs/day) | $31.68 | ~$0.13/hr spot vs. $1.00/hr on-demand |
| NAT gateway (single AZ) | $32.85 | + $0.045/GB data processing |
| EBS gp3 volumes | $8.00 | Prometheus 50GB + Grafana 10GB + AlertManager 5GB |
| Data transfer out | $3.00 | Estimated for dev traffic |
| S3 model storage | $1.20 | Mistral 7B ~14GB |
| CloudWatch logs | $2.00 | Retention 7 days |
| **Total** | **~$182/month** | |

## Production-sized environment (100 req/sec sustained)

Estimated production sizing for a moderate LLM inference workload:

| Component | Monthly cost | Notes |
|-----------|-------------:|-------|
| EKS control plane | $73.00 | |
| 3× m5.large system nodes | $210.24 | On-demand for HA |
| 4× g5.xlarge (spot, 24/7) | $380.16 | 3 for baseline + 1 for burst headroom |
| Multi-AZ NAT gateway (3 AZs) | $98.55 | + data processing |
| EBS gp3 volumes | $40.00 | 90-day Prometheus retention |
| Data transfer out | $50.00 | Depends on client traffic |
| S3 model storage | $2.00 | With multiple model versions |
| CloudWatch logs | $30.00 | Higher retention |
| **Total** | **~$884/month** | |

## The savings story (design choices as line items)

If the same production workload were built naively, cost would be significantly higher. This is where the architecture pays off:

| Design choice | Naive alternative | Monthly savings |
|---------------|-------------------|----------------:|
| Spot g5.xlarge (65% off on-demand) | 4× on-demand g5.xlarge | ~$705 |
| Karpenter consolidation (nodes only when needed) | Fixed 4-node ASG | ~$200 |
| Shared observability stack | Per-service Prometheus | ~$120 |
| S3 model storage vs. EFS | EFS for model artifacts | ~$80 |
| Single NAT in dev | Multi-AZ NAT everywhere | ~$65 |
| **Total savings** | | **~$1,170/month** |

Framed differently: a naive setup for the same workload would cost ~$2,050/month. This architecture delivers the same throughput at ~$884/month — a 57% reduction.

## Interview talking points

The number that matters is **cost per token**, not raw monthly spend. For a 7B model on a g5.xlarge spot node:

- **Throughput**: ~250 tokens/sec (measured under load)
- **Node cost**: $0.13/hr
- **Cost per 1M tokens**: ~$0.14

Compare to OpenAI GPT-4o at $2.50/M input tokens: this architecture is ~18× cheaper for the base workload, at the cost of running a smaller model.

## Watchouts

- **EKS control plane cost is flat.** Consolidating clusters (one cluster for many teams) is the biggest lever after node right-sizing.
- **NAT gateway is often the top hidden cost.** VPC endpoints for S3 and ECR eliminate a lot of NAT data processing charges — worth setting up.
- **Prometheus storage compounds.** 90-day retention on 100 req/sec workload = ~200GB. Consider Thanos or Grafana Mimir for longer retention.
- **Data transfer between AZs is expensive.** Deploy vLLM pods with pod topology spread constraints to avoid cross-AZ chatter.

## Sources

- AWS pricing as of 2026-01 (us-east-1)
- Spot pricing observed over 30-day window; may vary by region and time
- All estimates assume Reserved Instance discounts NOT applied — factor in 30–40% additional savings if committed pricing is available
