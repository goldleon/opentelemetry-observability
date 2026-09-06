terraform {
  required_version = ">= 1.5.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.26.0"
    }
  }
}

variable "namespace" {
  type        = string
  default     = "opentelemetry"
  description = "Kubernetes namespace for OpenTelemetry components"
}

resource "kubernetes_namespace" "otel" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}

# Deploy OpenTelemetry Operator
resource "helm_release" "opentelemetry_operator" {
  name       = "opentelemetry-operator"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-operator"
  version    = "0.52.0"
  namespace  = kubernetes_namespace.otel.metadata[0].name

  set {
    name  = "manager.collectorImage.repository"
    value = "otel/opentelemetry-collector-contrib"
  }

  set {
    name  = "admissionWebhooks.certManager.enabled"
    value = "true"
  }
}

# Output status
output "operator_release_status" {
  value       = helm_release.opentelemetry_operator.status
  description = "Helm release status of OpenTelemetry Operator"
}
