# =============================================================================
# Default StorageClass - gp3
# =============================================================================
# Fresh EKS clusters ship with NO default StorageClass. Any PVC that does not
# explicitly specify storageClassName (which is most Helm charts, including
# kube-prometheus-stack) stays Pending forever.
#
# Depends on the EBS CSI driver addon being installed (see cluster_addons
# in main.tf). The provisioner "ebs.csi.aws.com" is served by that addon.
# =============================================================================

resource "kubernetes_storage_class_v1" "gp3_default" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }

  depends_on = [module.eks]
}