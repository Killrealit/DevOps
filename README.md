# URL Shortener — End-to-End DevOps Portfolio Project

Production-ready сервис сокращения ссылок на **FastAPI + PostgreSQL + Redis** с полным циклом автоматизации инфраструктуры, CI/CD, безопасности и наблюдаемости (Observability).

## Архитектура и стек технологий

* **Application:** Python 3.12 (FastAPI, SQLAlchemy Async, asyncpg, Redis Cache-Aside, `prometheus-fastapi-instrumentator`).
* **Containerization:** Multi-stage `Dockerfile` на базе `python:3.12-slim` с запуском от непривилегированного пользователя (`UID 1000`) и `readOnlyRootFilesystem`.
* **IaC & Configuration Management:**
  * **Ansible:** автоматическая подготовка хоста (Ubuntu 24.04), установка Docker, `kubectl`, `helm`, `kind` и настройка локального DNS.
  * **Terraform:** разворачивание локального Kubernetes-кластера (`Kind`), установка NGINX Ingress Controller, PostgreSQL, Redis и `kube-prometheus-stack`.
* **Kubernetes & Helm:** кастомный Helm-чарт (`helm/shortener-app`) с поддержкой `HPA`, `Liveness/Readiness` проб, `SecurityContext`, `ServiceMonitor` и автоматическим перезапуском подов при изменении `ConfigMap`/`Secret` (`checksum` аннотации).
* **CI/CD & DevSecOps:** GitHub Actions (`.github/workflows/deploy.yml`) с линтингом (`hadolint`, `flake8`, `helm lint`), юнит-тестами (`pytest`), сканированием образов (`Trivy`), публикацией в `ghcr.io` и деплоем на `self-hosted` раннер.
* **Monitoring:** Prometheus + Grafana + кастомные `PrometheusRule` алерты (`monitoring/alert-rules.yml`).

---

## Структура репозитория

```text
├── .github/workflows/
│   └── deploy.yml          # CI/CD пайплайн (Lint -> Test -> Build -> Trivy -> Helm Deploy)
├── ansible/
│   ├── inventory.ini       # Инвентарь локального узла
│   └── playbook.yml        # Установка Docker, K8s CLI, Helm, Kind и настройка /etc/hosts
├── app/
│   ├── Dockerfile          # Multi-stage сборка без root-прав
│   ├── main.py             # FastAPI приложение + /health, /ready, /metrics
│   ├── requirements.txt    # Зависимости Python
│   └── test_main.py        # Юнит-тесты (pytest)
├── helm/shortener-app/     # Кастомный Helm-чарт (Deployment, Service, Ingress, HPA, ServiceMonitor)
├── monitoring/
│   └── alert-rules.yml     # Правила алертинга PrometheusRule
├── terraform/
│   ├── main.tf             # Разворачивание Kind кластера, Ingress, Postgres, Redis, Monitoring
│   ├── outputs.tf          # Выходные параметры кластера
│   └── variables.tf        # Переменные инфраструктуры
└── docker-compose.yml      # Локальный запуск для разработки
```

---

## Быстрый старт

### 1. Подготовка хоста (Ansible)
```bash
sudo apt update && sudo apt install -y ansible
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml
```

### 2. Разворачивание Kubernetes-кластера и зависимостей (Terraform)
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 3. Локальный деплой приложения через Helm
```bash
helm upgrade --install shortener-app ./helm/shortener-app \
  --namespace shortener \
  --create-namespace
```

### 4. Проверка работы сервиса
```bash
# Создание короткой ссылки
curl -X POST http://shortener.local \
  -H "Content-Type: application/json" \
  -d '{"url": "https://github.com"}'

# Проверка метрик Prometheus
curl http://shortener.local
```
