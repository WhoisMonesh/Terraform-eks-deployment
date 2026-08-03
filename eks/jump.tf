####################################################################
#
# Creates a security group and EC2 instances that act as jump /
# bastion servers with kubectl access to the cluster.
#
# The jump servers reuse the worker node IAM role and instance
# profile, because the KodeKloud playground only permits PassRole
# on the course role (eksWorkerNodeRole).
#
####################################################################

# Allow the jump server to reach the EKS API so kubectl can authenticate.
# This policy is attached to the shared worker node role.
resource "aws_iam_policy" "jump_server_policy" {
  name        = "MoneshJumpServerPolicy"
  path        = "/"
  description = "Permissions for the jump servers to access the EKS cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks:ListClusters"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jump_server_cluster_access" {
  policy_arn = aws_iam_policy.jump_server_policy.arn
  role       = aws_iam_role.node_instance_role.name
}

# Security group for the jump servers
resource "aws_security_group" "jump_server_sg" {
  name        = "MoneshJumpServerSecurityGroup"
  description = "Security group for the jump servers"
  vpc_id      = data.aws_vpc.default_vpc.id
  tags = {
    "Name" = "MoneshJumpServerSecurityGroup"
  }
}

# Allow SSH from your public IP only
resource "aws_vpc_security_group_ingress_rule" "jump_server_ssh" {
  description       = "Allow SSH from my public IP"
  security_group_id = aws_security_group.jump_server_sg.id
  cidr_ipv4         = "${trimspace(data.http.my_ip.response_body)}/32"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "TCP"
}

# Allow outbound traffic so the jump servers can reach the internet
resource "aws_vpc_security_group_egress_rule" "jump_server_egress_all" {
  description       = "Allow jump server egress to anywhere"
  security_group_id = aws_security_group.jump_server_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Allow the jump servers to reach the EKS API server directly (default cluster
# API endpoint is public)
resource "aws_vpc_security_group_ingress_rule" "jump_server_to_master_443" {
  description                  = "Allow jump server to reach the EKS API server on 443"
  security_group_id            = aws_eks_cluster.monesh_eks.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = aws_security_group.jump_server_sg.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "TCP"
}

# The two jump servers. They install the AWS CLI and kubectl, then configure
# kubeconfig so they can manage the cluster.
resource "aws_instance" "jump_server" {
  count                  = var.jump_server_count
  ami                    = data.aws_ssm_parameter.jump_server_ami.value
  instance_type          = var.jump_server_instance_type
  subnet_id              = data.aws_subnets.public.ids[count.index]
  key_name               = aws_key_pair.eks_kp.key_name
  vpc_security_group_ids = [aws_security_group.jump_server_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.node_instance_profile.name
  associate_public_ip_address = true

  depends_on = [
    aws_eks_access_policy_association.jump_server_admin
  ]

  user_data_base64 = base64encode(<<EOF
    #!/bin/bash
    set -o xtrace

    # Install AWS CLI v2
    dnf install -y unzip > /dev/null
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q -o /tmp/awscliv2.zip -d /tmp/aws
    /tmp/aws/install > /dev/null

    # Install kubectl matching the cluster version
    curl -sLO "https://dl.k8s.io/release/v${var.cluster_version}.0/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    # Configure kubeconfig for the cluster
    /usr/local/bin/aws eks update-kubeconfig \
        --region ${var.aws_region} \
        --name ${var.cluster_name}

    echo "Jump server ready for: kubectl get nodes"
    EOF
  )

  tags = {
    Name = format("Monesh-Jump-Server-%d", count.index + 1)
  }
}