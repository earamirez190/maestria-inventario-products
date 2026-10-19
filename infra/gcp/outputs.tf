output "cluster_name" {
  value = google_container_cluster.gke.name
}

output "cloud_sql_connection_name" {
  value = google_sql_database_instance.inventory.connection_name
}

output "data_service_gsa" {
  value = google_service_account.data_service.email
}

output "otel_collector_gsa" {
  value = google_service_account.otel_collector.email
}

output "artifact_registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}
