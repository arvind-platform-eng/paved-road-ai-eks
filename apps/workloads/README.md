# Workloads

Model deployments served by the platform. Each subfolder is one model.

## Current workloads

| Model | Path | GPU | Notes |
|-------|------|-----|-------|
| Mistral 7B Instruct v0.3 | `mistral-7b/` | 1× A10G | vLLM · 8k context · bfloat16 |

## Adding a new model

1. Create a folder `<model-name>/`
2. Add an `inferenceservice.yaml` following the Mistral 7B pattern
3. Add a `kustomization.yaml` referencing it
4. Commit and push — ArgoCD picks it up on next sync (if wired into the ApplicationSet)

## Rules for every workload

- Must have a `nodeSelector: workload-type: gpu` and toleration for `nvidia.com/gpu`
- Must set `terminationGracePeriodSeconds: 300` for graceful drain
- Must expose the vLLM metrics endpoint (`/metrics` on the same port)
- Must have `startupProbe` with high `failureThreshold` — model loading takes time
- Should reference model weights from S3, never bake into the container image
