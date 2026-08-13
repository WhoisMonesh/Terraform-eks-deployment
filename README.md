# Terraform EKS Deployment

Deploys an Amazon EKS cluster named **Monesh-Eks-Cluster** following the same workflow as the [KodeKloud Amazon EKS course](https://learn.kodekloud.com/user/courses/aws-eks).

- EKS control plane with an *unmanaged* node group (deployed and joined manually, like the course)
- IAM roles use the KodeKloud course names (`eksClusterRole`, `eksWorkerNodeRole`, `eksPolicy`) because the playground only allows `PassRole` on those roles
- **Two jump servers (bastions)** `Monesh-Jump-Server-1` / `Monesh-Jump-Server-2` with `kubectl` access to the cluster
- Load balancer + EBS CSI permissions policy for worker nodes
- AWS LoadBalancer controller + sample 2048 game manifests under `resources/loadbalancer`

## Quick start (one-shot)

**IMPORTANT**: All resources are created in `us-east-1` (N. Virginia).

`deploy.sh` runs the entire workflow with a single command. It also fixes the two most common AWS CloudShell problems automatically:

- **`terraform: command not found`** — Terraform is downloaded and installed to `/tmp` if it is missing (kubectl too).
- **`no space left on device` on `terraform init`** — in CloudShell it sets `TF_DATA_DIR=/tmp/tfdata` so the providers live on the larger `/tmp` partition instead of the small home directory.

```bash
git clone https://github.com/WhoisMonesh/Terraform-eks-deployment
cd Terraform-eks-deployment
bash deploy.sh
```

The script runs the pre-flight checks, `terraform init` / `plan` / `apply`, creates a `kubeconfig`, joins the worker nodes, and prints the deployment summary (jump server IPs + SSH commands).

### Commands

| Command | What it does |
|---|---|
| `bash deploy.sh` | Install tools if needed, plan + apply, join worker nodes |
| `bash deploy.sh plan` | Pre-flight checks + `terraform plan` only |
| `bash deploy.sh nodes` | Set up kubeconfig + join the worker nodes |
| `bash deploy.sh addons` | Install cert-manager + AWS LoadBalancer controller + sample 2048 game |
| `bash deploy.sh destroy` | Destroy all resources |

- Set `AUTO_APPROVE=true` (e.g. `AUTO_APPROVE=true bash deploy.sh`) to skip the confirmation prompts.
- Run it from anywhere; the script `cd`s into `eks/` itself.
- Requires the AWS CLI to be installed and configured (CloudShell includes it).

## Connect to the cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name Monesh-Eks-Cluster
kubectl get nodes
```

The two jump servers share the `eksWorkerNodeRole` IAM role, so `kubectl get nodes` works from either one:

```bash
ssh -i ~/.ssh/eks-monesh.pem ec2-user@<jump-server-public-ip>
kubectl get nodes
```

`deploy.sh` prints ready-to-use `ssh_command_jump_1` / `ssh_command_jump_2`. Note: SSH ingress is only allowed from the public IP you ran the deployment from.

## Load balancing add-ons

Installed with `bash deploy.sh addons`:

1. [cert-manager](https://cert-manager.io/docs/) (TLS certificates for controller webhooks)
2. Subnet tagging for the LoadBalancer controller
3. `IngressClass`
4. AWS LoadBalancer controller
5. (Optional) sample 2048 game

Once the load balancer for the 2048 game is `Active` in the [loadbalancers view](https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#LoadBalancers:), copy its DNS name, put `http://` in front and open it in your browser.

## Outputs

`terraform output` (also printed at the end of `deploy.sh`):

| Output | Description |
|---|---|
| `NodeInstanceRole` | Worker node IAM role ARN (needed for the aws-auth ConfigMap) |
| `NodeAutoScalingGroup` | Worker node autoscaling group |
| `NodeSecurityGroup` | Worker node security group |
| `jump_server_public_ips` | Public IPs of the two jump servers |
| `ssh_command_jump_1` / `ssh_command_jump_2` | Ready-to-use SSH commands |

The apply also generates an SSH keypair and saves the private key to `~/.ssh/eks-monesh.pem` (chmod 600).

## Repository layout

```
├── deploy.sh                    # One-shot deploy / destroy / add-ons script
├── eks/                         # All Terraform configuration
│   ├── check-environment.sh     # Pre-flight checks (Linux/Mac/CloudShell)
│   ├── check-environment.ps1    # Pre-flight checks (Windows PowerShell)
│   ├── modules/
│   │   ├── create-service-role/ # Creates the EKS service role
│   │   └── use-service-role/    # Reuses an existing EKS service role
│   └── *.tf                     # Terraform resources
└── resources/loadbalancer/      # LoadBalancer controller + test app manifests
```

## Manual deploy (reference)

For a step-by-step walkthrough, or if you prefer not to use `deploy.sh`:

1. Configure AWS credentials (first time only):

    ```bash
    aws configure
    # Access Key ID, Secret Access Key, region = us-east-1, output = json
    ```

1. Run the environment check. It verifies the region, default VPC, internet gateway and pre-existing roles, and sets the Terraform variables accordingly.

    * **Windows PowerShell**: `.\check-environment.ps1`
    * **Otherwise** (KodeKloud lab terminal, CloudShell, any Linux or Mac):

        ```bash
        source check-environment.sh
        ```

1. Initialize, plan and apply from the `eks/` directory:

    ```bash
    cd Terraform-eks-deployment/eks
    terraform init
    terraform plan
    terraform apply        # type yes when prompted
    ```

    > **AWS CloudShell only**: CloudShell's home partition is too small for the Terraform providers, so `terraform init` may fail with `no space left on device`. Point Terraform's data directory at the larger `/tmp` partition and re-export it for every subsequent command:
    >
    > ```bash
    > mkdir -p /tmp/tfdata
    > export TF_DATA_DIR=/tmp/tfdata
    > ```

1. Join the worker nodes:

    ```bash
    aws eks update-kubeconfig --region us-east-1 --name Monesh-Eks-Cluster
    curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/aws-auth-cm.yaml
    ```

    Edit `aws-auth-cm.yaml` and replace `<ARN of instance role (not instance profile)>` with the `NodeInstanceRole` from `terraform output`:

    ```yaml
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: aws-auth
      namespace: kube-system
    data:
      mapRoles: |
        - rolearn: <ARN of instance role (not instance profile)> # <- EDIT THIS
          username: system:node:{{EC2PrivateDNSName}}
          groups:
            - system:bootstrappers
            - system:nodes
    ```

    ```bash
    kubectl apply -f aws-auth-cm.yaml
    kubectl get nodes -o wide   # wait ~60 seconds for nodes to join
    ```

## Clean up

When finished, delete all resources to avoid unwanted charges (this is not a production-grade deployment):

```bash
bash deploy.sh destroy
# or, manually:
# cd eks && terraform destroy
```

Type `yes` when prompted (or use `AUTO_APPROVE=true bash deploy.sh destroy`).
