# ADR 0001: Choose vLLM as the inference engine

**Status:** Accepted
**Date:** 2026-01-15
**Author:** Arvind Kumar

## Context

The reference architecture needs an inference engine to serve open-weight LLMs (7B–70B parameters) with the following requirements:

- High throughput (>100 tokens/sec on a single A10G GPU for 7B models)
- OpenAI-compatible API (drop-in for downstream clients)
- Actively maintained by a credible open-source community
- Reasonable memory efficiency — able to fit 7B model + KV cache in 24GB VRAM

Options considered: vLLM, HuggingFace Text Generation Inference (TGI), NVIDIA Triton with TensorRT-LLM, MLC-LLM.

## Decision

Use vLLM as the primary inference engine.

## Consequences

### Positive

- **PagedAttention gives 2–4× higher throughput** than TGI at the same GPU cost. This directly reduces per-request cost.
- **OpenAI-compatible API server** ships with vLLM — downstream applications need no code changes.
- **Continuous batching** natively — no separate batcher needed.
- **Broad model support** — Mistral, Llama, Qwen, Gemma all work out of the box.
- **Docker image is production-ready** — `vllm/vllm-openai:latest` needs no customisation for common cases.

### Negative

- **Cold-start time is significant** — 7B model with bfloat16 takes ~90 seconds to load. Mitigated with generous `startupProbe.failureThreshold`.
- **Memory allocation is greedy** — vLLM reserves 90% of GPU memory by default. This is intentional for KV cache efficiency but means you can't co-locate other GPU workloads on the same pod.
- **Version churn is high** — vLLM releases weekly. Pin to a specific version tag, not `latest`.

### Rejected alternatives

- **Text Generation Inference (TGI)** — simpler to run but 2–4× slower throughput. Acceptable trade-off only if operational simplicity dominates cost concerns; that's not this project.
- **NVIDIA Triton with TensorRT-LLM** — best raw performance but requires model-specific optimisation and TensorRT engine building. Too much friction for a reference architecture.
- **MLC-LLM** — impressive on-device inference but not designed for high-throughput server workloads.

## References

- [vLLM: PagedAttention paper](https://arxiv.org/abs/2309.06180)
- [TGI vs vLLM benchmarks](https://github.com/vllm-project/vllm/blob/main/benchmarks/README.md)
