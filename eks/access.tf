####################################################################
#
# Grants the worker node IAM role (used by the nodes and the jump
# servers) cluster admin access via EKS access entries.
#
####################################################################

# Access entry for the node / jump server role
resource "aws_eks_access_entry" "node_role" {
  cluster_name  = aws_eks_cluster.monesh_eks.name
  principal_arn = aws_iam_role.node_instance_role.arn
  type          = "STANDARD"
}

# Associate the cluster admin policy with the node / jump server role
resource "aws_eks_access_policy_association" "jump_server_admin" {
  cluster_name  = aws_eks_cluster.monesh_eks.name
  principal_arn = aws_iam_role.node_instance_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
