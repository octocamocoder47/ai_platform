output "aws_mimir_ingestor_role_arn" {
  value = var.aws_mimir_ingestor_role != "" ? var.aws_mimir_ingestor_role : try(aws_iam_role.mimir_ingestor[0].arn, "")
}

output "gcp_mimir_writer_sa" {
  value = var.gcp_mimir_writer_sa != "" ? var.gcp_mimir_writer_sa : try(google_service_account.mimir_writer[0].email, "")
}

output "aws_grafana_workspace_id" {
  value = var.enable_cross_cloud_dashboard ? try(aws_grafana_workspace.main[0].id, "") : ""
}

output "gcp_grafana_workspace_id" {
  value = var.enable_cross_cloud_dashboard ? try(google_grafana_workspace.main[0].id, "") : ""
}
