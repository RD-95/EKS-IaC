output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_ip" {
  description = "Public IP of the NAT Gateway"
  value       = module.vpc.nat_gateway_ip
}

output "eks_cluster_role_arn" {
  description = "IAM role ARN for the EKS control plane"
  value       = module.iam.cluster_role_arn
}

output "eks_node_role_arn" {
  description = "IAM role ARN for the EKS worker nodes"
  value       = module.iam.node_role_arn
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Run this to configure kubectl"
  value       = module.eks.kubeconfig_command
}

output "node_group_name" {
  description = "EKS node group name"
  value       = module.node_group.node_group_name
}
