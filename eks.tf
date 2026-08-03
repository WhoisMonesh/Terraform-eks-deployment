####################################################################
#
# Creates the EKS Cluster control plane and its service role
#
####################################################################

data "aws_iam_policy_document" "assume_role_eks" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM role assumed by the EKS control plane
resource "aws_iam_role" "cluster_role" {
  name               = var.cluster_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_eks.json
  path               = "/"
}

resource "aws_iam_role_policy_attachment" "cluster_role_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster_role.name
}

resource "aws_iam_role_policy_attachment" "cluster_role_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.cluster_role.name
}

resource "aws_iam_role_policy_attachment" "cluster_role_loadbalancer" {
  policy_arn = aws_iam_policy.loadbalancer_policy.arn
  role       = aws_iam_role.cluster_role.name
}

resource "aws_eks_cluster" "monesh_eks" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster_role.arn

  vpc_config {
    subnet_ids = [
      data.aws_subnets.public.ids[0],
      data.aws_subnets.public.ids[1],
      data.aws_subnets.public.ids[2]
    ]
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_role_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_role_AmazonEKSServicePolicy,
    aws_iam_role_policy_attachment.cluster_role_loadbalancer
  ]
}
