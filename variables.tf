####################################################################
#
# Variables used. All have defaults
#
####################################################################

variable "aws_region" {
  type        = string
  description = "AWS region to deploy the cluster into"
  default     = "us-east-1"
}

# Cluster must be called 'Monesh-Eks-Cluster'
variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
  default     = "Monesh-Eks-Cluster"
}

# Kubernetes version to deploy. Keep in sync with the node AMI below.
variable "cluster_version" {
  type        = string
  description = "Kubernetes version of the EKS control plane"
  default     = "1.31"
}

# Cluster IAM service role name
variable "cluster_role_name" {
  type        = string
  description = "Name of the EKS cluster service role"
  default     = "Monesh-Eks-Cluster-Role"
}

# Worker node IAM role name
variable "node_role_name" {
  type        = string
  description = "Name of the worker node IAM role"
  default     = "Monesh-Eks-Worker-Role"
}

# IAM policy created for load balancer / EBS CSI permissions
variable "additional_policy_name" {
  type        = string
  description = "Name of IAM policy created for additional permissions"
  default     = "Monesh-Eks-Policy"
}

# Jump server (bastion) IAM role name
variable "jump_server_role_name" {
  type        = string
  description = "Name of the IAM role assumed by the jump servers"
  default     = "Monesh-Jump-Server-Role"
}

# Number of jump servers to create
variable "jump_server_count" {
  type        = number
  description = "Number of jump servers (bastions) to create"
  default     = 2
}

variable "jump_server_instance_type" {
  type        = string
  description = "Instance type of the jump servers"
  default     = "t3.micro"
}

variable "node_group_desired_capacity" {
  type        = number
  description = "Desired capacity of Node Group ASG."
  default     = 2
}

variable "node_group_max_size" {
  type        = number
  description = "Maximum size of Node Group ASG. Set to at least 1 greater than node_group_desired_capacity."
  default     = 3
}

variable "node_group_min_size" {
  type        = number
  description = "Minimum size of Node Group ASG."
  default     = 1
}
