#!/usr/bin/env bash
# Печатает kubeconfig (base64, одной строкой) для секрета GitHub KUBE_CONFIG.
# Использование: ./ci/make-kubeconfig.sh <публичный IP мастера>
# Нужен текущий kubectl-контекст с правами администратора.
set -euo pipefail
MASTER_IP="${1:?Укажите публичный IP мастера: terraform output -raw master_public_ip}"
NS=diploma

kubectl apply -f "$(dirname "$0")/rbac.yaml" >&2
# токен заполняется контроллером не мгновенно
for _ in $(seq 1 15); do
  TOKEN_B64=$(kubectl -n "$NS" get secret ci-deployer-token -o jsonpath='{.data.token}')
  [ -n "$TOKEN_B64" ] && break
  sleep 1
done
[ -n "${TOKEN_B64:-}" ] || { echo "Токен не появился" >&2; exit 1; }
TOKEN=$(printf '%s' "$TOKEN_B64" | base64 -d)
CA=$(kubectl -n "$NS" get secret ci-deployer-token -o jsonpath='{.data.ca\.crt}')

cat <<KCFG | base64 -w0
apiVersion: v1
kind: Config
clusters:
  - name: diploma
    cluster:
      server: https://${MASTER_IP}:6443
      certificate-authority-data: ${CA}
users:
  - name: ci-deployer
    user:
      token: ${TOKEN}
contexts:
  - name: diploma
    context:
      cluster: diploma
      user: ci-deployer
      namespace: ${NS}
current-context: diploma
KCFG
echo >&2
