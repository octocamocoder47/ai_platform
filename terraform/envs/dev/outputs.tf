output "vpc_id" {
  description = "VPC ID"
  value       = try(module.network[0].vpc_id, null)
}

output "vpc_cidr" {
  description = "VPC CIDR"
  value       = try(module.network[0].vpc_cidr, null)
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = try(module.eks[0].cluster_name, null)
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = try(module.eks[0].cluster_endpoint, null)
}

output "eks_cluster_ca_cert" {
  description = "EKS cluster CA certificate"
  value       = try(module.eks[0].cluster_ca_cert, null)
  sensitive   = true
}

output "eks_oidc_provider_arn" {
  description = "OIDC provider ARN"
  value       = try(module.eks[0].oidc_provider_arn, null)
}

output "eks_oidc_provider_url" {
  description = "OIDC provider URL"
  value       = try(module.eks[0].oidc_provider_url, null)
}

output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = try(module.network[0].transit_gateway_id, null)
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = try(module.network[0].private_subnet_ids, null)
}

output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = try(module.gke[0].cluster_name, null)
}

output "irsa_roles" {
  description = "IRSA role ARNs"
  value       = try(module.irsa[0].irsa_roles, null)
}

output "state_bucket" {
  description = "Terraform state bucket"
  value       = "ai-platform-tfstate-${data.aws_caller_identity.current.account_id}"
}
