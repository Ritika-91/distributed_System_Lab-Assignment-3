#!/usr/bin/env bash
set -euo pipefail

kubectl config current-context
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/backend-deploy.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/client-deploy.yaml
kubectl apply -f k8s/client-service.yaml

echo "Waiting for pods..."
kubectl -n lab3 wait --for=condition=ready pod -l app=backend --timeout=120s || true
kubectl -n lab3 wait --for=condition=ready pod -l app=client --timeout=120s || true

kubectl -n lab3 get pods,svc -o wide
