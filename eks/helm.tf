# eks/helm.tf
# Install core observability and tooling stack via Helm charts

# Disabled Elasticsearch and Kibana Helm releases due to unavailable chart versions
#resource "helm_release" "elasticsearch" {
#  name              = "elasticsearch"
#  repository        = "https://helm.elastic.co"
#  chart             = "elasticsearch"
#  namespace         = "elastic"
#  create_namespace  = true
#  version           = "8.12.0"
#  depends_on        = [aws_eks_cluster.monesh_eks]
#}

#resource "helm_release" "kibana" {
#  name              = "kibana"
#  repository        = "https://helm.elastic.co"
#  chart             = "kibana"
#  namespace         = "elastic"
#  create_namespace  = false
#  version           = "8.12.0"
#  depends_on        = [aws_eks_cluster.monesh_eks]
#}

# Disabled JFrog Artifactory Helm release due to unavailable chart version
#resource "helm_release" "artifactory" {
#  name              = "artifactory"
#  repository        = "https://charts.jfrog.io"
#  chart             = "artifactory-oss"
#  namespace         = "artifactory"
#  create_namespace  = true
#  version           = "108.19.13"
#  depends_on        = [aws_eks_cluster.monesh_eks]
#}
