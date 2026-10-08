#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap-storage.sh
# Creates the default gp3 StorageClass for the cluster.
#
# WHY MANUAL: Fresh EKS clusters do not ship with a default StorageClass.
# Without one, PVCs without an explicit storageClassName stay Pending.
# This script creates gp3 as the default.
#
# RUN THIS: Immediately after `terraform apply` completes successfully.
# Idempotent: safe to re-run.
# ---------------------------------------------------------------------------
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
