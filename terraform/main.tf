terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16.0"
    }
  }
}

resource "kind_cluster" "default" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      kubeadm_config_patches = [
        <<-EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }

      extra_port_mappings {
        container_port = 443
        host_port      = 443
      }
    }

    node {
      role = "worker"
    }
  }
}

provider "kubernetes" {
  host                   = kind_cluster.default.endpoint
  client_certificate     = kind_cluster.default.client_certificate
  client_key             = kind_cluster.default.client_key
  cluster_ca_certificate = kind_cluster.default.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.default.endpoint
    client_certificate     = kind_cluster.default.client_certificate
    client_key             = kind_cluster.default.client_key
    cluster_ca_certificate = kind_cluster.default.cluster_ca_certificate
  }
}

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_namespace
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://github.io"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.hostPort.enabled"
    value = "true"
  }
  set {
    name  = "controller.service.type"
    value = "NodePort"
  }
  set {
    name  = "controller.watchIngressWithoutClass"
    value = "true"
  }
  set {
    name  = "controller.nodeSelector.ingress-ready"
    value = "true"
  }
  set {
    name  = "controller.tolerations.key"
    value = "node-role.kubernetes.io/control-plane"
  }
  set {
    name  = "controller.tolerations.operator"
    value = "Equal"
  }
  set {
    name  = "controller.tolerations.effect"
    value = "NoSchedule"
  }

  depends_on = [kind_cluster.default]
}

resource "helm_release" "postgresql" {
  name       = "postgres"
  repository = "https://bitnami.com"
  chart      = "postgresql"
  namespace  = kubernetes_namespace.app.metadata.name

  set {
    name  = "auth.username"
    value = "shortener_user"
  }
  set_sensitive {
    name  = "auth.password"
    value = var.postgres_password
  }
  set {
    name  = "auth.database"
    value = "shortener"
  }
  set {
    name  = "primary.persistence.size"
    value = "1Gi"
  }
}

resource "helm_release" "redis" {
  name       = "redis"
  repository = "https://bitnami.com"
  chart      = "redis"
  namespace  = kubernetes_namespace.app.metadata.name

  set {
    name  = "architecture"
    value = "standalone"
  }
  set {
    name  = "auth.enabled"
    value = "false"
  }
  set {
    name  = "master.persistence.enabled"
    value = "false"
  }
}

resource "helm_release" "monitoring" {
  name       = "kube-prometheus-stack"
  repository = "https://github.io"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata.name

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }
}
