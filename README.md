# Terraform EKS Deployment

Deploys an Amazon EKS cluster named **Monesh-Eks-Cluster** with:

- **EKS control plane** (self-managed / unmanaged node group, course style)
- IAM roles named after the owner: `Monesh-Eks-Cluster-Role`, `Monesh-Eks-Worker-Role`, `Monesh-Eks-Policy`, `Monesh-Jump-Server-Role`
- **Two jump servers (bastions)** that automatically install `kubectl` + AWS CLI and are granted cluster admin via EKS access entries, so `kubectl get nodes` works from either server
- Load balancer + EBS CSI permissions policy for worker nodes

## Prerequisites

- AWS CLI configured with credentials in `us-east-1`
- Terraform >= 1.3
- A default VPC in the region with public subnets in AZs `a`, `b`, `c` and an internet gateway

## Step-by-step deployment

Run these commands in order. They assume you have an IAM user with `AdministratorAccess` (or at least EKS + EC2 + IAM + CloudFormation permissions).

### 1. Clone the repo

```bash
git clone https://github.com/WhoisMonesh/Terraform-eks-deployment.git
cd Terraform-eks-deployment
```

### 2. Configure AWS credentials (one time)

```bash
aws configure
# Access Key ID, Secret Access Key, region = us-east-1, output = json
```

Verify you're authenticated:

```bash
aws sts get-caller-identity
```

### 3. Deploy the cluster

```bash
terraform init
terraform apply -auto-approve
```

What this creates:

- EKS cluster `Monesh-Eks-Cluster` (control plane, no worker nodes yet)
- Worker node IAM role + security groups + launch template
- Autoscaling group with `t3.medium` worker nodes (desired 2)
- Two jump servers `Monesh-Jump-Server-1` and `Monesh-Jump-Server-2`
- IAM roles: `Monesh-Eks-Cluster-Role`, `Monesh-Eks-Worker-Role`, `Monesh-Jump-Server-Role`

The apply also generates an SSH keypair and saves the private key to `~/.ssh/eks-monesh.pem` (chmod 600).

> Note: full deployment takes roughly **8-15 minutes** (cluster creation + node bootstrapping).

### 4. Check the outputs

```bash
terraform output
```

### 5. Confirm the cluster is up

```bash
aws eks update-kubeconfig --region us-east-1 --name Monesh-Eks-Cluster
kubectl get nodes
```

You should see 2 worker nodes in `Ready` state (it takes a few minutes for the nodes to join).

## Connect to the cluster

From either jump server (SSH from the machine whose public IP matches your current IP):

```bash
ssh -i ~/.ssh/eks-monesh.pem ec2-user@<jump-server-public-ip>
kubectl get nodes
```

Or from your local machine (needs `kubectl` + `aws` CLI, and an IAM identity that is cluster admin, e.g. the one that ran `terraform apply`):

```bash
aws eks update-kubeconfig --region us-east-1 --name Monesh-Eks-Cluster
kubectl get nodes
```

## Outputs

| Output | Description |
|---|---|
| `cluster_endpoint` | EKS API server endpoint |
| `node_autoscaling_group` | Worker node autoscaling group |
| `jump_server_public_ips` | Public IPs of the two jump servers |
| `ssh_command_jump_1` / `ssh_command_jump_2` | Ready-to-use SSH commands |

## Clean up

```bash
terraform destroy -auto-approve
```
