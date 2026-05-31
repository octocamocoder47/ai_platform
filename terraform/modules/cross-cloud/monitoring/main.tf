# Cross-Cloud Monitoring — Grafana Mimir cross-cloud metrics federation

locals {
  name_prefix = var.name_prefix != "" ? var.name_prefix : "ai-platform"
}

# IAM policy for cross-cloud metric ingestion
resource "aws_iam_role" "mimir_ingestor" {
  count = var.aws_mimir_ingestor_role == "" ? 1 : 0

  name = "${local.name_prefix}-mimir-ingestor"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "accounts.google.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "accounts.google.com:sub" = var.gcp_workload_identity_subject
        }
      }
    }]
  })
}

resource "aws_iam_policy" "mimir_ingestor" {
  count = var.aws_mimir_ingestor_role == "" ? 1 : 0

  name = "${local.name_prefix}-mimir-ingestor"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:RemoteWrite",
        "aps:GetSeries",
        "aps:QueryMetrics",
      ]
      Resource = var.aws_mimir_workspace_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "mimir_ingestor" {
  count = var.aws_mimir_ingestor_role == "" ? 1 : 0

  role       = aws_iam_role.mimir_ingestor[0].name
  policy_arn = aws_iam_policy.mimir_ingestor[0].arn
}

# GCP Service Account for Mimir remote write
resource "google_service_account" "mimir_writer" {
  count = var.gcp_mimir_writer_sa == "" ? 1 : 0

  provider = google.primary

  project     = var.gcp_project_id
  account_id  = "${local.name_prefix}-mimir-writer"
  display_name = "Mimir Remote Write - ${local.name_prefix}"
}

resource "google_project_iam_member" "mimir_writer" {
  count = var.gcp_mimir_writer_sa == "" ? 1 : 0

  provider = google.primary

  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.mimir_writer[0].email}"
}

# CloudWatch → Mimir metric stream (via CloudWatch Metric Stream to Firehose → Lambda)
resource "aws_cloudwatch_metric_stream" "mimir" {
  name          = "${local.name_prefix}-to-mimir"
  role_arn      = var.firehose_role_arn
  firehose_arn  = var.firehose_arn
  output_format = "opentelemetry0.7"

  include_filter {
    namespace = var.cloudwatch_namespace
  }
}

# Grafana Cloud forwarding for unified cross-cloud dashboard
resource "aws_grafana_workspace" "main" {
  count = var.enable_cross_cloud_dashboard ? 1 : 0

  name          = "${local.name_prefix}-cross-cloud"
  account_access_type = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type         = "SERVICE_MANAGED"

  data_sources = ["CLOUDWATCH", "PROMETHEUS", "XRAY"]
}

resource "google_grafana_workspace" "main" {
  count = var.enable_cross_cloud_dashboard ? 1 : 0

  provider = google.primary

  project  = var.gcp_project_id
  location = var.gcp_region
  name     = "${local.name_prefix}-cross-cloud"
}
