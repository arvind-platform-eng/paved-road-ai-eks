# Platform ApplicationSet

Deploys the shared cluster-wide platform components via ArgoCD.

## What's here

| Component | Purpose | Version |
|-----------|---------|---------|
| cert-manager | TLS certificate provisioning (Let's Encrypt) | 1.16.1 |
| ingress-nginx | Ingress controller, terminates traffic at NLB | 4.11.3 |
| knative-serving | Serverless runtime for KServe | 1.15.6 |
| kserve | InferenceService CRD + controller | 0.13.1 |

## Design

The ApplicationSet uses the **list generator** — each element becomes an ArgoCD Application. Adding a new platform component is one YAML block.

```yaml
- name: my-component
  namespace: my-namespace
  repoURL: https://charts.example.com
  chart: my-chart
  version: 1.2.3
  values: |
    # Helm values here
```

## Why ApplicationSet over individual Applications

- **Single source of truth** — one file lists every platform component
- **Consistent sync policy** — all components sync the same way
- **Easy diffs** — updating a version is a one-line change
