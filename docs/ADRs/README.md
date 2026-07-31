# Architecture Decision Records

Design decisions worth capturing — the trade-offs behind the code.

## Format

Each ADR follows this structure:
- **Context** — what problem we're solving
- **Decision** — what we chose
- **Consequences** — good and bad outcomes
- **Rejected alternatives** — what we considered but didn't pick, and why

## Records

| # | Title | Status |
|---|-------|--------|
| [0001](0001-choose-vllm.md) | Choose vLLM as the inference engine | Accepted |
| [0002](0002-choose-karpenter.md) | Choose Karpenter for GPU node autoscaling | Accepted |
| [0003](0003-use-kserve.md) | Use KServe for model serving abstraction | Accepted |

## Why ADRs

Every architecture decision has three possible explanations later: "obvious", "regretted", or "forgotten". ADRs turn the forgotten ones into the first two.
