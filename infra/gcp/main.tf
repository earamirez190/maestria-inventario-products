terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "google_project_service" "apis" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "container.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com",
    "sqladmin.googleapis.com",
    "iamcredentials.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = var.artifact_repository
  description   = "Images del laboratorio integrador de observabilidad"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

resource "google_container_cluster" "gke" {
  name                     = var.cluster_name
  location                 = var.zone
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [google_project_service.apis]
}

resource "google_container_node_pool" "primary" {
  name       = "primary"
  location   = var.zone
  cluster    = google_container_cluster.gke.name
  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}

resource "google_sql_database_instance" "inventory" {
  name             = var.sql_instance_name
  database_version = "MYSQL_8_0"
  region           = var.region
  deletion_protection = false

  settings {
    tier              = var.sql_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    backup_configuration {
      enabled = true
    }
    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "inventory" {
  name     = var.sql_database_name
  instance = google_sql_database_instance.inventory.name
}

resource "google_sql_user" "inventory" {
  name     = var.sql_user
  instance = google_sql_database_instance.inventory.name
  password = var.sql_password
}

resource "google_service_account" "data_service" {
  account_id   = "data-service-gsa"
  display_name = "Data Service Cloud SQL identity"
}

resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.data_service.email}"
}

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.data_service.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[actividad1/data-service]"
}
