# Версии чартов зафиксированы для воспроизводимости
INGRESS_CHART_VERSION ?= 4.15.1
KPS_CHART_VERSION     ?= 92.14.1

.PHONY: help repos ingress monitoring app all status

help:
	@echo "make ingress     - ingress-nginx на worker1 (hostPort 80/443)"
	@echo "make monitoring  - kube-prometheus-stack на узле monitoring (нужен GRAFANA_PASSWORD)"
	@echo "make app         - тестовое приложение (kustomize, каталог app/)"
	@echo "make all         - всё по порядку и проверка"
	@echo "make status      - состояние узлов, подов и ingress"

repos:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update

ingress: repos
	helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
		--version $(INGRESS_CHART_VERSION) --namespace ingress-nginx --create-namespace \
		-f ingress-nginx/values.yaml --wait --timeout 5m

monitoring: repos
	@test -n "$$GRAFANA_PASSWORD" || { echo "Задайте пароль Grafana: export GRAFANA_PASSWORD='...'"; exit 1; }
	kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n monitoring create secret generic grafana-admin \
		--from-literal=admin-user=admin --from-literal=admin-password="$$GRAFANA_PASSWORD" \
		--dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
		--version $(KPS_CHART_VERSION) --namespace monitoring \
		-f monitoring/values.yaml --wait --timeout 15m

app:
	kubectl apply -k app
	kubectl -n diploma rollout status deployment/diploma-app --timeout=3m

all: ingress monitoring app status

status:
	kubectl get nodes -L role
	kubectl get pods -A -o wide | grep -E 'NAMESPACE|ingress-nginx|monitoring|diploma'
	kubectl get ingress -A
