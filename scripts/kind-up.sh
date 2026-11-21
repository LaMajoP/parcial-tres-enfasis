#!/usr/bin/env bash
set -euo pipefail
command -v kind >/dev/null || { echo "Instale Kind para esta verificación local." >&2; exit 69; }
command -v kubectl >/dev/null || { echo "Instale kubectl para esta verificación local." >&2; exit 69; }
command -v docker >/dev/null || { echo "Instale Docker para esta verificación local." >&2; exit 69; }
kind create cluster --name aegisvolt --wait 60s
# El controlador es necesario para que un recurso Rollout se ejecute realmente.
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/download/v1.8.3/install.yaml
kubectl -n argo-rollouts rollout status deployment/argo-rollouts --timeout=3m
for component in graphql-gateway station-reservation billing-wallet energy-dispatch; do
  docker build --target runtime -t "aegisvolt/$component:0.0.0" .
done
docker build --target web-runtime -t aegisvolt/web:0.0.0 .
kind load docker-image aegisvolt/graphql-gateway:0.0.0 aegisvolt/station-reservation:0.0.0 aegisvolt/billing-wallet:0.0.0 aegisvolt/energy-dispatch:0.0.0 aegisvolt/web:0.0.0 --name aegisvolt
# DynamoDB Local conserva su volumen aunque Kind se elimine. Ejecutar el
# bootstrap como tarea efímera en cada arranque completa tablas/semillas
# faltantes de forma condicional, sin borrar ni sustituir operaciones previas.
docker compose build dynamodb-init
docker compose up -d dynamodb-local
docker compose run --rm dynamodb-init
DDB_ID=$(docker compose ps -q dynamodb-local)
docker network connect kind "$DDB_ID" 2>/dev/null || true
DDB_IP=$(docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' "$DDB_ID")
test -n "$DDB_IP"

kubectl apply -k infra/kubernetes/overlays/kind

kubectl -n aegisvolt-dev patch configmap aegisvolt-runtime --type=merge \
  -p "{\"data\":{\"DYNAMODB_ENDPOINT\":\"http://${DDB_IP}:8000\",\"AWS_ACCESS_KEY_ID\":\"local\",\"AWS_SECRET_ACCESS_KEY\":\"local\"}}"

kubectl -n aegisvolt-dev patch networkpolicy domain-service-ingress-egress --type=json \
  -p "[{\"op\":\"add\",\"path\":\"/spec/egress/-\",\"value\":{\"to\":[{\"ipBlock\":{\"cidr\":\"${DDB_IP}/32\"}}],\"ports\":[{\"protocol\":\"TCP\",\"port\":8000}]}}]"

# KIND_GATEWAY_DYNAMODB_FIX
kubectl -n aegisvolt-dev patch networkpolicy gateway-ingress-egress --type=json \
  -p "[{\"op\":\"add\",\"path\":\"/spec/egress/-\",\"value\":{\"to\":[{\"ipBlock\":{\"cidr\":\"${DDB_IP}/32\"}}],\"ports\":[{\"protocol\":\"TCP\",\"port\":8000}]}}]"

kubectl -n aegisvolt-dev rollout restart deployment/station-reservation deployment/billing-wallet deployment/energy-dispatch
# El ConfigMap se parchea después de aplicar el overlay, por lo que también se
# reinicia el Rollout: las cuatro réplicas del gateway deben recibir el endpoint
# dinámico de DynamoDB Local y no depender de una carrera durante el arranque.
kubectl -n aegisvolt-dev rollout restart rollout/graphql-gateway

kubectl -n aegisvolt-dev rollout status deployment/station-reservation --timeout=3m
kubectl -n aegisvolt-dev rollout status deployment/billing-wallet --timeout=3m
kubectl -n aegisvolt-dev rollout status deployment/energy-dispatch --timeout=3m
# No se requiere el plugin de cliente de Argo Rollouts. El CRD publica las
# condiciones Healthy/Available, que kubectl estándar puede esperar y que son
# producidas por el controlador instalado arriba.
kubectl -n aegisvolt-dev wait --for=condition=Healthy rollout/graphql-gateway --timeout=5m
kubectl -n aegisvolt-dev wait --for=condition=Available rollout/graphql-gateway --timeout=5m
kubectl -n aegisvolt-dev get pods,services,rollouts
