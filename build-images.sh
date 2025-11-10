#!/usr/bin/env bash
set -euo pipefail

# Build jars
mvn -f backend/pom.xml clean package -DskipTests
mvn -f client/pom.xml clean package -DskipTests

# Build docker images (Docker Desktop: same daemon as k8s)
docker build -t backend:1.0 ./backend
docker build -t client:1.0 ./client

echo "Images built: backend:1.0 and client:1.0"

