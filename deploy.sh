#!/usr/bin/env bash
# =============================================================================
#  deploy.sh - One-shot EKS deployment script
# -----------------------------------------------------------------------------
#  Fixes "terraform: command not found" in AWS CloudShell by downloading and
#  installing Terraform (and kubectl, if missing) on the fly. It also points
#  TF_DATA_DIR at /tmp because CloudShell's home partition is too small for
#  the Terraform providers, then runs the full KodeKloud-style workflow:
#  pre-flight checks -> terraform init -> plan -> apply -> kubeconfig ->
#  join the worker nodes.
#
#  Usage:
#     bash deploy.sh            Full deploy (install tools, plan, apply, join nodes)
#     bash deploy.sh plan       Pre-flight checks + terraform plan only
#     bash deploy.sh nodes      Set up kubeconfig + join the worker nodes only
#     bash deploy.sh addons     Install cert-manager + AWS LoadBalancer controller
#     bash deploy.sh destroy    Destroy all resources
#
#  Options:
#     AUTO_APPROVE=true   skip the confirmation prompt on apply / destroy
# =============================================================================
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="Monesh-Eks-Cluster"
TF_VERSION="1.9.8"
TF_INSTALL_DIR="/tmp/tf-bin"
KB_INSTALL_DIR="/tmp/kb-bin"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EKS_DIR="$ROOT/eks"

IS_CLOUDSHELL=false
[[ "${AWS_EXECUTION_ENV:-}" == "CloudShell" ]] && IS_CLOUDSHELL=true

info() { printf '\033[0;36m[deploy]\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m[deploy]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[deploy]\033[0m %s\n' "$*"; }
err()  { printf '\033[0;31m[deploy]\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1
}

install_terraform() {
  warn "terraform not found - installing v$TF_VERSION to $TF_INSTALL_DIR ..."
  local uname_s uname_m url
  uname_s="$(uname -s | tr '[:upper:]' '[:lower:]')"
  uname_m="$(uname -m)"
  case "$uname_s" in darwin) uname_s="darwin" ;; linux) uname_s="linux" ;; esac
  case "$uname_m" in x86_64|amd64) uname_m="amd64" ;; aarch64|arm64) uname_m="arm64" ;; esac
  url="https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${uname_s}_${uname_m}.zip"
  mkdir -p "$TF_INSTALL_DIR"
  curl -fsSLo /tmp/terraform.zip "$url"
  require unzip || err "unzip is required to install terraform"
  unzip -oq /tmp/terraform.zip -d "$TF_INSTALL_DIR"
  export PATH="$TF_INSTALL_DIR:$PATH"
  ok "terraform $TF_VERSION installed"
}

install_kubectl() {
  warn "kubectl not found - installing to $KB_INSTALL_DIR ..."
  local uname_s uname_m kb_version
  uname_s="$(uname -s | tr '[:upper:]' '[:lower:]')"
  uname_m="$(uname -m)"
  case "$uname_s" in darwin) uname_s="darwin" ;; linux) uname_s="linux" ;; esac
  case "$uname_m" in x86_64|amd64) uname_m="amd64" ;; aarch64|arm64) uname_m="arm64" ;; esac
  kb_version="$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || echo v1.31.0)"
  mkdir -p "$KB_INSTALL_DIR"
  curl -fsSLo "$KB_INSTALL_DIR/kubectl" \
    "https://dl.k8s.io/release/${kb_version}/bin/${uname_s}/${uname_m}/kubectl"
  chmod +x "$KB_INSTALL_DIR/kubectl"
  export PATH="$KB_INSTALL_DIR:$PATH"
  ok "kubectl ${kb_version} installed"
}

preflight() {
  info "Pre-flight checks ..."
  require aws || err "aws cli is not installed. Use AWS CloudShell or install it first."
  require curl || err "curl is not installed."
  require unzip || warn "unzip is not installed (needed only to install terraform/kubectl)."
  require jq || warn "jq is not installed."

  if ! require terraform; then install_terraform; fi
  if ! require kubectl; then install_kubectl; fi

  if [[ "$IS_CLOUDSHELL" == true ]]; then
    export TF_DATA_DIR=/tmp/tfdata
    mkdir -p /tmp/tfdata
    warn "CloudShell detected - TF_DATA_DIR=$TF_DATA_DIR"
  fi

  export AWS_REGION="$REGION"
  export AWS_DEFAULT_REGION="$REGION"

  local current
  current="$(aws configure get region 2>/dev/null || true)"
  if [[ "$current" != "$REGION" ]]; then
    warn "Default AWS region is '${current:-unset}' - forcing region to $REGION for this run."
  fi

  local vpc igw
  vpc="$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)"
  [[ "$vpc" != "None" ]] || err "No default VPC found in $REGION."
  ok "Using default VPC: $vpc"
  igw="$(aws ec2 describe-internet-gateways --region "$REGION" --filters "Name=attachment.vpc-id,Values=$vpc" --query "InternetGateways[0].InternetGatewayId" --output text)"
  [[ "$igw" != "None" ]] || err "Default VPC $vpc has no Internet Gateway attached."
  ok "Default VPC has Internet Gateway: $igw"

  if aws iam get-role --role-name eksClusterRole >/dev/null 2>&1; then
    export TF_VAR_use_predefined_role=true
    ok "Using pre-existing role eksClusterRole"
  else
    export TF_VAR_use_predefined_role=false
    warn "eksClusterRole not present - Terraform will create it."
  fi
  ok "Pre-flight checks passed"
}

tf_init() {
  info "terraform init ..."
  terraform -chdir="$EKS_DIR" init -input=false
}

tf_plan() {
  info "terraform plan ..."
  terraform -chdir="$EKS_DIR" plan
}

tf_apply() {
  info "terraform apply ... (this can take up to 10 minutes)"
  local flag=()
  if [[ "${AUTO_APPROVE:-false}" == "true" ]]; then flag+=(-auto-approve); fi
  terraform -chdir="$EKS_DIR" apply "${flag[@]:-}"
}

join_nodes() {
  info "Setting up kubeconfig for $CLUSTER_NAME ..."
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

  local role_arn
  role_arn="$(terraform -chdir="$EKS_DIR" output -raw NodeInstanceRole)"
  ok "NodeInstanceRole: $role_arn"

  info "Creating aws-auth ConfigMap to join the worker nodes ..."
  cat > /tmp/aws-auth-cm.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: $role_arn
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
EOF
  kubectl apply -f /tmp/aws-auth-cm.yaml

  info "Waiting for worker nodes to become Ready (up to 5 minutes) ..."
  if ! kubectl wait --for=condition=Ready nodes --all --timeout=300s; then
    warn "Nodes not ready yet. Run 'kubectl get nodes' shortly."
  fi
  kubectl get nodes -o wide
}

addons() {
  info "Installing cert-manager ..."
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.20.2/cert-manager.yaml
  kubectl -n cert-manager rollout status deployment/cert-manager --timeout=300s || true

  info "Tagging subnets for the LoadBalancer controller ..."
  bash "$ROOT/resources/loadbalancer/tag-subnets.sh"

  info "Installing IngressClass ..."
  kubectl apply -f "$ROOT/resources/loadbalancer/ingress-class.yaml"

  info "Installing AWS LoadBalancer controller ..."
  kubectl apply -f "$ROOT/resources/loadbalancer/loadbalancer_v2_7_2_full.yaml"
  kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=300s || true

  ok "Add-ons installed. Optional: kubectl apply -f $ROOT/resources/loadbalancer/2048-full.yaml"
}

destroy() {
  info "terraform destroy ..."
  local flag=()
  if [[ "${AUTO_APPROVE:-false}" == "true" ]]; then flag+=(-auto-approve); fi
  terraform -chdir="$EKS_DIR" destroy "${flag[@]:-}"
  ok "Cleanup complete"
}

show_outputs() {
  info "Deployment summary:"
  terraform -chdir="$EKS_DIR" output
  printf '\n\033[0;33mSSH into the jump servers:\033[0m\n'
  terraform -chdir="$EKS_DIR" output ssh_command_jump_1
  terraform -chdir="$EKS_DIR" output ssh_command_jump_2
}

CMD="${1:-deploy}"
cd "$ROOT"

case "$CMD" in
  deploy)
    preflight
    tf_init
    tf_plan
    tf_apply
    join_nodes
    show_outputs
    ok "Cluster deployed. Run 'bash deploy.sh addons' to install the LoadBalancer controller."
    ;;
  plan)
    preflight
    tf_init
    tf_plan
    ;;
  nodes)
    preflight
    join_nodes
    ;;
  addons)
    preflight
    addons
    ;;
  destroy)
    preflight
    destroy
    ;;
  *)
    err "Unknown command: $CMD (use: deploy | plan | nodes | addons | destroy)"
    ;;
esac
