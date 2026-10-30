# diploma-k8s

Конфигурация Kubernetes-кластера для дипломного проекта: ingress, мониторинг и тестовое приложение.

## Структура репозиториев

| Репозиторий | Содержимое |
|---|---|
| `diploma-infra`| `terraform/bootstrap`, `terraform/infra`, `ansible/`, workflow Terraform |
| `diploma-k8s` (этот) | манифесты и values: kube-prometheus, ingress-nginx, Grafana, приложение |
| `diploma-app` | nginx-конфиг, статика, Dockerfile, workflow сборки и деплоя |

```
diploma-k8s/
├── ingress-nginx/values.yaml  # ingress-nginx на worker1 через hostPort 80/443
├── monitoring/values.yaml     # kube-prometheus-stack (на узле с меткой role=monitoring)
├── app/                       # тестовое приложение: namespace, deployment, service, ingress (kustomize)
└── Makefile                   # ingress, monitoring, app, all, status
```

## Требования

Кластер установлен (`diploma-infra`: `make up`), на локальной машине есть `kubectl` и `helm`, образ приложения опубликован в реестре
(`diploma-app`: `make push`).

## Развёртывание

```bash
kubectl get nodes -L role                # у узла monitoring в колонке ROLE: monitoring
export GRAFANA_PASSWORD='<пароль>'       # пароль администратора Grafana 
make all
```

Или по шагам: `make ingress`, `make monitoring`, `make app`, `make status`.

## Доступ (порт 80)

Адрес: публичный IP `worker1`: `terraform output -raw ingress_public_ip` в `diploma-infra/terraform/infra`.

| Что | Адрес |
|---|---|
| Тестовое приложение | `http://<IP>/` |
| Grafana | `http://<IP>/grafana` (логин `admin`, пароль из `GRAFANA_PASSWORD`) |

Приложение и Grafana работают на одном адресе и порту, их разделяют пути. IP в манифестах не хранится: после
`terraform destroy` и `apply` адрес меняется, а конфигурация остаётся прежней.

Prometheus и Alertmanager наружу не публикуются:
```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093
```

Дашборды Kubernetes в Grafana: *Kubernetes / Compute Resources / Cluster*, *Node Exporter / Nodes*, *Kubernetes / Kubelet*.
Алерт `Watchdog` в Alertmanager горит всегда, это штатная проверка работоспособности цепочки алертинга.

## Размещение

| Компонент | Узел |
|---|---|
| ingress-nginx | worker1 (статический IP, порты 80 и 443 на ВМ) |
| Prometheus, Alertmanager, Grafana, operator, kube-state-metrics | monitoring |
| node-exporter | все узлы (DaemonSet) |
| приложение (2 реплики) | любые рабочие узлы |

Узлы `monitoring` и `worker1` прерываемые: Yandex Cloud останавливает их через 24 часа,
запускать нужно вручную: `yc compute instance start diploma-monitoring diploma-worker1`. После запуска кластер
восстанавливается сам. Данные Prometheus хранятся на `emptyDir`, при остановке узла они теряются.

## Обновление версии приложения

Тег образа задаётся в `app/kustomization.yaml` (`images[].newTag`):
```bash
cd app && kustomize edit set image cr.yandex/crppb6ltiiiam8vg56g8/diploma-app=cr.yandex/crppb6ltiiiam8vg56g8/diploma-app:v0.2.0
kubectl apply -k .
```
Позже этот шаг выполняет CI/CD при создании git-тега.

## Замечания

- **ingress-nginx закрыт сообществом**: с марта 2026 проект не получает исправлений безопасности
  ([объявление Kubernetes](https://www.kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)). Установленные
  развёртывания продолжают работать, для учебного стенда это приемлемо. Для замены подойдёт любой другой Ingress-контроллер
  (например, Traefik): изменятся `ingress-nginx/values.yaml` и поле `ingressClassName` в манифестах.
- Если `hostPort` не откроет порт 80 на worker1, в `ingress-nginx/values.yaml` вместо него можно включить
  `controller.hostNetwork: true` и `controller.dnsPolicy: ClusterFirstWithHostNet`.
- Метрики etcd, scheduler, controller-manager и kube-proxy отключены: в кластере Kubespray они слушают только localhost.
