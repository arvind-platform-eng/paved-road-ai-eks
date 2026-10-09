#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap-argocd.sh
# Installs ArgoCD and configures it for a tainted-system-nodes cluster.
# Run after terraform apply completes (phase 3 of deploy sequence).
#
# Idempotent: safe to re-run.
# ---------------------------------------------------------------------------
set -euo pipefail

# 1. Namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# 2. ArgoCD install (stable manifests)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. ApplicationSet CRD (not in stable; use server-side for 262KB limit)
kubectl apply --server-side -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/crds/applicationset-crd.yaml

echo ""
echo "Waiting 10s for manifests to settle..."
sleep 10

# 4. Patch tolerations so pods schedule on tainted system nodes
echo "Patching tolerations..."
for deploy in $(kubectl get deployment -n argocd -o name); do
  kubectl patch "$deploy" -n argocd --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"CriticalAddonsOnly","operator":"Exists","effect":"NoSchedule"}]}]' || true
done
for sts in $(kubectl get statefulset -n argocd -o name); do
  kubectl patch "$sts" -n argocd --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"CriticalAddonsOnly","operator":"Exists","effect":"NoSchedule"}]}]' || true
done

# 5. Delete any Pending pods so they get rescheduled with new tolerations
kubectl delete pods -n argocd --field-selector=status.phase=Pending --ignore-not-found

echo ""
echo "Waiting for all ArgoCD pods to be Ready (up to 5 min)..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/part-of=argocd -n argocd --timeout=300s || true

echo ""
echo "=========================================="
echo "Initial admin password (SAVE THIS NOW):"
echo "=========================================="
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "ArgoCD ready."
echo "Access UI:  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Then open:  https://localhost:8080  (admin + password above)"
echo ""
echo "Next step - apply the root Application for GitOps:"
echo "  kubectl apply -f apps/bootstrap/application.yaml"
