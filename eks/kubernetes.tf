# eks/kubernetes.tf
# Configure Kubernetes and Helm providers to talk to the newly created EKS cluster

data "aws_eks_cluster" "cluster" {
  name       = var.cluster_name
  depends_on = [aws_eks_cluster.monesh_eks]
}

data "aws_eks_cluster_auth" "auth" {
  name       = var.cluster_name
  depends_on = [aws_eks_cluster.monesh_eks]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.auth.token
}

