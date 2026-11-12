output "cluster_endpoint" {
  description = "API endpoint локального кластера Kubernetes"
  value       = kind_cluster.default.endpoint
}

output "kubeconfig_path" {
  description = "Путь к сгенерированному kubeconfig"
  value       = kind_cluster.default.kubeconfig_path
}

output "app_namespace" {
  description = "Namespace приложения"
  value       = kubernetes_namespace.app.metadata.name
}
