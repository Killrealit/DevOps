variable "cluster_name" {
  description = "Имя локального Kind кластера"
  type        = string
  default     = "devops-portfolio-cluster"
}

variable "app_namespace" {
  description = "Namespace для приложения url-shortener"
  type        = string
  default     = "shortener"
}

variable "postgres_password" {
  description = "Пароль для PostgreSQL"
  type        = string
  sensitive   = true
  default     = "changeme_in_ci"
}
