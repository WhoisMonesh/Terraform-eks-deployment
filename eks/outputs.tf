####################################################################
#
# Outputs
#
####################################################################

output "NodeInstanceRole" {
  value = aws_iam_role.node_instance_role.arn
}

output "NodeSecurityGroup" {
  value = aws_security_group.node_security_group.id
}

output "NodeAutoScalingGroup" {
  value = aws_cloudformation_stack.autoscaling_group.outputs["NodeAutoScalingGroup"]
}

output "cluster_name" {
  value = aws_eks_cluster.monesh_eks.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.monesh_eks.endpoint
}

output "cluster_certificate_authority" {
  value = aws_eks_cluster.monesh_eks.certificate_authority[0].data
}

output "cluster_role_arn" {
  value = var.use_predefined_role ? module.use_eksClusterRole[0].eksClusterRole_arn : module.create_eksClusterRole[0].eksClusterRole_arn
}

output "jump_server_iam_role_arn" {
  value = aws_iam_role.node_instance_role.arn
}

output "jump_server_public_ips" {
  value = aws_instance.jump_server[*].public_ip
}

output "jump_server_private_ips" {
  value = aws_instance.jump_server[*].private_ip
}

output "ssh_command_jump_1" {
  value = var.jump_server_count >= 1 ? format("ssh -i ~/.ssh/eks-monesh.pem ec2-user@%s", aws_instance.jump_server[0].public_ip) : null
}

output "ssh_command_jump_2" {
  value = var.jump_server_count >= 2 ? format("ssh -i ~/.ssh/eks-monesh.pem ec2-user@%s", aws_instance.jump_server[1].public_ip) : null
}
