# ADR 0003: Use KServe for model serving abstraction

**Status:** Accepted
**Date:** 2026-01-15
**Author:** Arvind Kumar

## Context

We need an abstraction layer between the raw Kubernetes Deployment and the inference workload. Without one, every team building on the platform ends up reinventing:

- Model versioning and blue/green rollouts
- Request-based autoscaling (CPU-based scaling is a poor proxy for LLM load)
- Model artifact fetching from cloud storage
- OpenAI-compatible routing across model versions

## Decision

Use KServe `InferenceService` as the workload abstraction. Serve vLLM inside `InferenceService` predictors.

## Consequences

### Positive

- **Model versioning is declarative** — canary traffic split between `mistral-7b:v1` and `mistral-7b:v2` is one YAML field.
- **Storage-initializer abstracts model fetch** — declare `storageUri: s3://bucket/mistral-7b`, KServe pulls it before the container starts. No custom init containers.
- **KServe autoscaling is queue-based** — better fit for LLM workloads than raw HPA on CPU. We use `containerConcurrency` to shape scaling behaviour.
- **Consistent metrics surface** — all InferenceServices expose the same Prometheus metric names for latency, throughput, and error rate.
- **Supports both Serverless (Knative) and RawDeployment modes** — we start with RawDeployment for simpler operations; can switch to Knative for scale-to-zero later.

### Negative

- **Learning curve for teams** — an InferenceService is not a Deployment. Teams need docs and examples.
- **Additional operator to maintain** — KServe controller must be kept upgraded. Breaking changes have occurred between minor versions.
- **RawDeployment mode has fewer features than Knative** — no scale-to-zero, no revision management. Acceptable trade-off for simplicity in v1.

### Rejected alternatives

- **Raw Kubernetes Deployment** — no versioning story, no storage abstraction, no consistent metrics. Every team reinvents these.
- **Seldon Core** — comparable feature set but smaller community and more complex CRDs.
- **BentoML with Yatai** — good developer experience but requires teams to adopt a specific framework in the model repository. KServe is model-agnostic.

## Adoption path

1. Start with KServe `RawDeployment` mode (chosen)
2. Once Knative Serving is battle-tested in dev, evaluate switching to Serverless mode for scale-to-zero benefits
3. Consider KServe's ModelMesh for multi-model serving as usage grows

## References

- [KServe documentation](https://kserve.github.io/website/latest/)
- [KServe vLLM runtime docs](https://kserve.github.io/website/latest/modelserving/v1beta1/llm/vllm/)
