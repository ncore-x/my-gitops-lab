
resource "kubernetes_manifest" "nginx_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "nginx-app"
      namespace = "argocd"
    }
    spec = {
      ignoreDifferences = [
    {
      group   = "apps"
      kind    = "Deployment"
      jsonPointers = [
        "/spec/template/spec/containers/0/resources",
        "/spec/template/spec/volumes",
      ]
      project = "default"
      source = {
        repoURL        = "https://github.com/ncore-x/my-gitops-lab"
        targetRevision = "HEAD"
        path           = "k8s/apps/nginx"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "apps"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }

depends_on = [null_resource.argocd_install, kubernetes_namespace.apps]
}
