####################################################################
#
# Grants the jump server IAM role access to the EKS cluster using
# EKS access entries (authentication mode is API_AND_CONFIG_MAP).
#
####################################################################

# Access entry for the jump server role
resource "aws_eks_access_entry" "jump_server" {
  cluster_name  = aws_eks_cluster.monesh_eks.name
  principal_arn = aws_iam_role.jump_server_role.arn
  type          = "STANDARD"
}

# Associate the cluster admin policy with the jump server role
resource "aws_eks_access_policy_association" "jump_server_admin" {
  cluster_name  = aws_eks_cluster.monesh_eks.name
  principal_arn = aws_iam_role.jump_server_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
