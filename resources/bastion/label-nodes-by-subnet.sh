#!/usr/bin/env bash
# =============================================================================
#  label-nodes-by-subnet.sh
# -----------------------------------------------------------------------------
#  Labels every worker node with:
#     bastion-subnet=<Name tag of the subnet the node's EC2 instance is in>
#  so the bastion pod can be pinned to a subnet (e.g. management) with a
#  nodeSelector. Safe to re-run; existing labels are overwritten.
# =============================================================================
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"

nodes="$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')"
[[ -n "$nodes" ]] || { echo "No nodes found." >&2; exit 1; }

for node in $nodes; do
  provider_id="$(kubectl get node "$node" -o jsonpath='{.spec.providerID}')"
  instance_id="${provider_id##*/}"

  subnet_id="$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].SubnetId' \
    --output text)"

  name="$(aws ec2 describe-subnets \
    --region "$REGION" \
    --subnet-ids "$subnet_id" \
    --query 'Subnets[0].Tags[?Key==`Name`].Value | [0]' \
    --output text)"

  if [[ "$name" == "None" || -z "$name" ]]; then
    echo "WARN: subnet $subnet_id has no Name tag; skipping node $node"
    continue
  fi

  kubectl label node "$node" "bastion-subnet=$name" --overwrite >/dev/null
  echo "node $node -> subnet '$name'"
done
