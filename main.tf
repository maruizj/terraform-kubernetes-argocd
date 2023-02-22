locals {
  extra_manifests = join(" ", var.manifests)

  # Remove map keys from all_repositories with no value. That means they were not specified
  clean_repositories = {
    for name, repo in var.repositories : "${name}" => {
      for k, v in repo : k => v if v != null
    }
  }

  # If no_auth_config has been specified, set all configs as null
  values = merge({
    global = {
      image = {
        tag = var.image_tag
      }
    }

    server = {
      config     = var.config
      rbacConfig = var.rbac_config
      # Run insecure mode if specified, to prevent argocd from using it's own certificate
      extraArgs = var.server_insecure ? ["--insecure"] : null
      # Ingress Values
      ingress = {
        enabled     = var.ingress_host != null ? true : false
        https       = true
        annotations = var.ingress_annotations
        hosts       = [var.ingress_host]
        tls = var.server_insecure ? [{
          secretName = var.ingress_tls_secret
          hosts      = [var.ingress_host]
        }] : null
      }
    }
    configs = {
      # Configmaps require strings, yamlencode the map
      repositories = local.clean_repositories
    }
  })
}

# ArgoCD Charts
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # force_update = true
  # dependency_update = true

  values = concat(
    [yamlencode(local.values), yamlencode(var.values)],
    [for x in var.values_files : file(x)]
  )
}

resource "null_resource" "extra_manifests" {
  count = length(local.extra_manifests) > 0 ? 1 : 0
  triggers = {
    extra_manifests = local.extra_manifests
  }

  provisioner "local-exec" {
    command = "kubectl apply -f '${self.triggers.extra_manifests}'"
    when    = create
  }
  provisioner "local-exec" {
    command = "kubectl delete -f '${self.triggers.extra_manifests}'"
    when    = destroy
  }

  depends_on = [helm_release.argocd]
}

