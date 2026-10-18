variable "project_id" {
  type        = string
  description = "Proyecto GCP propio donde se ejecutará el laboratorio"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "cluster_name" {
  type    = string
  default = "actividad1-gke"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "artifact_repository" {
  type    = string
  default = "actividad1-images"
}

variable "sql_instance_name" {
  type    = string
  default = "inventory-cloudsql"
}

variable "sql_database_name" {
  type    = string
  default = "inventorydb"
}

variable "sql_user" {
  type    = string
  default = "inventory"
}

variable "sql_password" {
  type      = string
  sensitive = true
}
