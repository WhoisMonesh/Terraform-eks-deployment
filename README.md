# Terraform EKS Deployment

Deploys an Amazon EKS cluster named **Monesh-Eks-Cluster** following the same workflow as the [KodeKloud Amazon EKS course](https://learn.kodekloud.com/user/courses/aws-eks).

- EKS control plane with an *unmanaged* node group (deployed and joined manually, like the course)
- IAM roles use the KodeKloud course names (`eksClusterRole`, `eksWorkerNodeRole`, `eksPolicy`) because the playground only allows `PassRole` on those roles
- **Two jump servers (bastions)** `Monesh-Jump-Server-1` / `Monesh-Jump-Server-2` with `kubectl` access to the cluster
- Load balancer + EBS CSI permissions policy for worker nodes
- AWS LoadBalancer controller + sample 2048 game manifests under `resources/loadbalancer`

The repository layout mirrors the KodeKloud course:

```
├── eks/                          # All Terraform configuration
│   ├── check-environment.sh      # Pre-flight checks (Linux/Mac/CloudShell)
│   ├── check-environment.ps1     # Pre-flight checks (Windows PowerShell)
│   ├── modules/
│   │   ├── create-service-role/  # Creates the EKS service role
│   │   └── use-service-role/     # Reuses an existing EKS service role
│   └── *.tf                      # Terraform resources
└── resources/loadbalancer/       # LoadBalancer controller + test app manifests
```

## Deploying the Cluster

**IMPORTANT**: Ensure that all resources are created in the `us-east-1` (N. Virginia) region.

### One-shot deploy (recommended)

`deploy.sh` automates the entire workflow below in a single command. It fixes
the two most common CloudShell problems for you:

- **`terraform: command not found`** — Terraform is downloaded and installed
  automatically to `/tmp` if it is missing (kubectl too).
- **`no space left on device` on `terraform init`** — in CloudShell it sets
  `TF_DATA_DIR=/tmp/tfdata` so the providers are stored on the larger `/tmp`
  partition instead of the small home directory.

It then runs the pre-flight checks, `terraform init` / `plan` / `apply`, sets
up `kubeconfig`, and joins the worker nodes.

```bash
git clone https://github.com/WhoisMonesh/Terraform-eks-deployment
cd Terraform-eks-deployment
bash deploy.sh            # full deploy
```

Subcommands:

| Command | What it does |
|---|---|
| `bash deploy.sh` | Install tools if needed, plan + apply, join worker nodes |
| `bash deploy.sh plan` | Pre-flight checks + `terraform plan` only |
| `bash deploy.sh nodes` | Set up kubeconfig + join the worker nodes |
| `bash deploy.sh addons` | Install cert-manager + AWS LoadBalancer controller + 2048 game manifests |
| `bash deploy.sh destroy` | Destroy all resources |

Set `AUTO_APPROVE=true` (e.g. `AUTO_APPROVE=true bash deploy.sh`) to skip the
confirmation prompts. Run from anywhere; the script `cd`s into `eks/` itself.

### Manual deploy

1. Clone the repository

    ```bash
    git clone https://github.com/WhoisMonesh/Terraform-eks-deployment
    ```

1. Navigate to the EKS directory

    ```bash
    cd Terraform-eks-deployment/eks
    ```

1. Configure AWS credentials (first time only)

    ```bash
    aws configure
    # Access Key ID, Secret Access Key, region = us-east-1, output = json
    ```

1. Run the environment check. It verifies the region, default VPC, internet gateway and pre-existing roles, and sets the Terraform variables accordingly.

    * If you are running from a **Windows PowerShell** terminal, run

        ```text
        .\check-environment.ps1
        ```

    * **Otherwise** (KodeKloud lab terminal, CloudShell, any Linux or Mac), run

        ```bash
        source check-environment.sh
        ```

1. Initialize Terraform

    ```bash
    terraform init
    ```

    > **AWS CloudShell only**: CloudShell's home partition is too small to hold the Terraform providers, so `terraform init` may fail with `no space left on device`. Work around it by pointing Terraform's data directory to the larger `/tmp` partition:
    >
    > ```bash
    > mkdir -p /tmp/tfdata
    > export TF_DATA_DIR=/tmp/tfdata
    > terraform init
    > ```
    >
    > You must keep `TF_DATA_DIR` exported for every subsequent `terraform` command in the same session (or re-export it each time).

1. Plan the deployment

    ```bash
    terraform plan
    ```

1. Apply the configuration. This creates the EKS control plane and the autoscaling group with worker nodes. This step can take up to 10 minutes.

    ```bash
    terraform apply
    ```

    When prompted, type `yes` to confirm.

1. Retrieve the outputs

    ```bash
    terraform output
    ```

    Note the `NodeInstanceRole`, `NodeAutoScalingGroup`, `NodeSecurityGroup` and the two `jump_server_public_ips`. The `NodeInstanceRole` value is needed in the next step to join the worker nodes.

    The apply also generates an SSH keypair and saves the private key to `~/.ssh/eks-monesh.pem` (chmod 600).

## Set up access and join nodes

1. Create a KUBECONFIG for `kubectl`

    ```bash
    aws eks update-kubeconfig --region us-east-1 --name Monesh-Eks-Cluster
    ```

1. Join the worker nodes

    1. Download the node authentication ConfigMap

        ```bash
        curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/aws-auth-cm.yaml
        ```

    1. Edit the ConfigMap YAML and add the `NodeInstanceRole` obtained from Terraform

        ```bash
        vi aws-auth-cm.yaml
        ```

        Replace the placeholder text `<ARN of instance role (not instance profile)>` with the value of `NodeInstanceRole`:

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

    1. Apply the edited ConfigMap

        ```bash
        kubectl apply -f aws-auth-cm.yaml
        ```

1. Wait around 60 seconds for the nodes to join.

1. Verify the nodes

    ```bash
    kubectl get node -o wide
    ```

    You should see the worker nodes in `Ready` state. Note that with EKS you do not see control plane nodes, as they are managed by AWS.

## Connect from the jump servers

The two jump servers share the `eksWorkerNodeRole` IAM role. Once you have applied the aws-auth ConfigMap above, the worker nodes (and the jump servers) can authenticate to the cluster, so `kubectl get nodes` works from either jump server.

```bash
ssh -i ~/.ssh/eks-monesh.pem ec2-user@<jump-server-public-ip>
kubectl get nodes
```

The `jump_server_public_ips` and `ssh_command_jump_1` / `ssh_command_jump_2` outputs give you the addresses and ready-to-use SSH commands. Note: SSH ingress is only allowed from the public IP you ran the deployment from.

## Cluster add-ons (load balancing)

1. Install [cert-manager](https://cert-manager.io/docs/), required for TLS certificates on controller webhooks:

    ```bash
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.20.2/cert-manager.yaml
    ```

    Wait for all pods in the `cert-manager` namespace to be running.

1. Tag the subnets so the LoadBalancer controller can identify them:

    ```bash
    ../resources/loadbalancer/tag-subnets.sh
    ```

1. Install the `IngressClass`:

    ```bash
    kubectl apply -f ../resources/loadbalancer/ingress-class.yaml
    ```

1. Install the load balancer controller:

    ```bash
    kubectl apply -f ../resources/loadbalancer/loadbalancer_v2_7_2_full.yaml
    ```

    Wait for the `aws-loadbalancer-controller` pod in the `kube-system` namespace to be running.

1. (Optional) Install the sample 2048 game:

    ```bash
    kubectl apply -f ../resources/loadbalancer/2048-full.yaml
    ```

    Wait for the new load balancer to become `Active` in the [loadbalancers view](https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#LoadBalancers:), copy its DNS name, put `http://` in front and open it in your browser.

## Outputs

| Output | Description |
|---|---|
| `NodeInstanceRole` | Worker node IAM role ARN (needed for the aws-auth ConfigMap) |
| `NodeAutoScalingGroup` | Worker node autoscaling group |
| `NodeSecurityGroup` | Worker node security group |
| `jump_server_public_ips` | Public IPs of the two jump servers |
| `ssh_command_jump_1` / `ssh_command_jump_2` | Ready-to-use SSH commands |

## Clean up

When finished, delete all resources to avoid unwanted charges (this is not a production-grade deployment):

```bash
terraform destroy
```

Type `yes` when prompted.
