# K8s + ArgoCD + Terraform на Minikube

Локальный GitOps стенд на macOS (Apple Silicon). Terraform управляет инфраструктурой кластера, ArgoCD синхронизирует Git-репозиторий с Kubernetes.

## Стек

- **Minikube** — локальный Kubernetes кластер
- **Terraform** — управление инфраструктурой (namespaces, ArgoCD, Application CRD)
- **ArgoCD** — GitOps-оператор, синхронизирует манифесты из Git в кластер
- **kubectl** — CLI для работы с кластером

---

## Предварительные требования

- macOS с Homebrew
- Docker Desktop (запущен)
- `kubectl` и `minikube` уже установлены

---

## Структура проекта

```
my-gitops-lab/
├── terraform/
│   ├── .gitignore
│   ├── versions.tf       # провайдеры и их версии
│   ├── argocd.tf         # установка ArgoCD через kubectl
│   ├── apps.tf           # namespace для приложений
│   └── argocd_app.tf     # ArgoCD Application CRD
└── k8s/
    └── apps/
        └── nginx/
            ├── deployment.yaml
            └── service.yaml
```

---

## Шаг 1 — Установка Terraform

Terraform убран из основного Homebrew, устанавливается через официальный tap HashiCorp:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform -version
```

---

## Шаг 2 — Запуск Minikube

ArgoCD требует минимум 2 CPU и 4 GB RAM:

```bash
minikube start --cpus=4 --memory=4096 --driver=docker
kubectl get nodes
```

---

## Шаг 3 — Terraform файлы

### terraform/.gitignore

```
.terraform/
.terraform.lock.hcl
*.tfstate
*.tfstate.backup
```

### terraform/versions.tf

```hcl
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}
```

### terraform/argocd.tf

> **Важно:** Helm-репозиторий `argoproj.github.io/argo-helm` может быть недоступен в ряде регионов.
> Поэтому ArgoCD устанавливается напрямую через `kubectl apply`.
> Флаги `--server-side --force-conflicts` обязательны — без них падает ошибка
> `metadata.annotations: Too long` на CRD `applicationsets.argoproj.io`.

```hcl
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "null_resource" "argocd_install" {
  provisioner "local-exec" {
    command = "kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts"
  }

  depends_on = [kubernetes_namespace.argocd]
}
```

### terraform/apps.tf

```hcl
resource "kubernetes_namespace" "apps" {
  metadata {
    name = "apps"
  }
}
```

### terraform/argocd_app.tf

> **Важно:** `kubernetes_manifest` валидирует CRD через API кластера во время `plan`.
> Если ArgoCD ещё не установлен — `plan` упадёт с ошибкой
> `no matches for kind "Application" in group "argoproj.io"`.
> Поэтому этот файл применяется **вторым проходом** (см. раздел «Первый запуск»).

```hcl
resource "kubernetes_manifest" "nginx_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "nginx-app"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/ВАШ_АККАУНТ/my-gitops-lab"
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
```

---

## Шаг 4 — Kubernetes манифесты

### k8s/apps/nginx/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
```

### k8s/apps/nginx/service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: apps
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
```

---

## Первый запуск

### Проход 1 — поднять ArgoCD

```bash
cd terraform/

# Убрать argocd_app.tf из области видимости
mv argocd_app.tf argocd_app.tf.bak

terraform init
terraform apply
```

Дождаться пока все поды ArgoCD перейдут в статус `Running` (1–2 минуты):

```bash
kubectl get pods -n argocd -w
```

Ожидаемый результат — 7 подов в статусе `Running`:

```
argocd-application-controller-0       1/1   Running
argocd-applicationset-controller-...  1/1   Running
argocd-dex-server-...                 1/1   Running
argocd-notifications-controller-...   1/1   Running
argocd-redis-...                      1/1   Running
argocd-repo-server-...                1/1   Running
argocd-server-...                     1/1   Running
```

### Проход 2 — создать ArgoCD Application

```bash
mv argocd_app.tf.bak argocd_app.tf
terraform apply
```

---

## Доступ к ArgoCD UI

```bash
# Пробросить порт (держать терминал открытым)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# В другом терминале — получить пароль admin
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Открыть в браузере: `https://localhost:8080`
Логин: `admin`, пароль — из команды выше.

---

## Повторный запуск (после перезагрузки / остановки)

```bash
# Запустить Minikube
minikube start

# Убедиться что контекст kubectl переключён на minikube
kubectl config use-context minikube

# Перейти в папку terraform и применить конфиг
cd terraform/
terraform apply
```

Terraform увидит что инфраструктура уже существует и ничего не пересоздаст:

```
No changes. Your infrastructure matches the configuration.
```

Если поды не запустились — проверить:

```bash
kubectl get pods -n argocd
kubectl get pods -n apps
```

---

## Остановка

```bash
# Остановить кластер (сохраняет состояние)
minikube stop
```

Для полного удаления всех ресурсов:

```bash
cd terraform/
terraform destroy

minikube delete
```

---

## Проверка работы GitOps цикла

Изменить количество реплик в `k8s/apps/nginx/deployment.yaml`:

```yaml
replicas: 3
```

Запушить в Git:

```bash
git add k8s/
git commit -m "scale nginx to 3 replicas"
git push
```

ArgoCD автоматически обнаружит изменение и применит его в кластер в течение ~3 минут.
Следить за синхронизацией:

```bash
kubectl get pods -n apps -w
```

Или принудительно синхронизировать через CLI:

```bash
argocd login localhost:8080 --username admin --insecure
argocd app sync nginx-app
argocd app get nginx-app
```

---

## Известные нюансы

| Проблема | Причина | Решение |
|---|---|---|
| `brew install terraform` — формула не найдена | Terraform убран из Homebrew core | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |
| `no matches for kind "Application"` при `plan` | `kubernetes_manifest` валидирует CRD до установки ArgoCD | Применять двумя проходами — сначала без `argocd_app.tf` |
| `metadata.annotations: Too long` на CRD | Лимит 256KB на аннотацию при client-side apply | Использовать `--server-side --force-conflicts` |
| Helm репозиторий `argoproj.github.io` недоступен | Сетевые ограничения | Устанавливать ArgoCD через `kubectl apply` напрямую |
| `null_resource` помечается как tainted после ошибки | Terraform считает provisioner упавшим | Обновить команду на `--server-side --force-conflicts` и применить снова |
