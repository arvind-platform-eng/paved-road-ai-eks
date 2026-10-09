#!/usr/bin/env bash
# Creates default gp3 StorageClass. Run after terraform apply completes.
# Idempotent — safe to re-run.
set -euo pipefail

kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
  encrypted: "true"
  fsType: ext4
EOF

echo ""
echo "Default gp3 StorageClass created."
echo "Verify: kubectl get storageclass"
