# Bootstrap

The root ArgoCD Application that manages every other Application via app-of-apps.

## Usage

After ArgoCD is installed (see main README quick start):

```bash
kubectl apply -f apps/bootstrap/application.yaml
```

This creates the root Application. It reads `apps/platform/` from this repo and syncs everything under it — cert-manager, ingress-nginx, KServe, etc.

## Design

- **App-of-apps pattern** — the root Application declares child Applications. This keeps the bootstrap process to a single `kubectl apply`.
- **Automated sync + prune + self-heal** — resources deleted from git are removed from the cluster. Resources modified out-of-band are reverted.

## What NOT to install here

Terraform manages Karpenter and observability directly because they need IAM setup that ArgoCD can't do. Everything else runs through ArgoCD.
