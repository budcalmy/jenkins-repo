#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 8 ]; then
  echo "Usage: $0 <EC2_HOST> <EC2_USER> <AWS_REGION> <ECR_REGISTRY> <ECR_IMAGE> <DEPLOY_TAG> <CONTAINER_NAME> <CONTAINER_PORT>" >&2
  exit 1
fi

EC2_HOST=$1
EC2_USER=$2
AWS_REGION=$3
ECR_REGISTRY=$4
ECR_IMAGE=$5
DEPLOY_TAG=$6
CONTAINER_NAME=$7
CONTAINER_PORT=$8

set -x

ssh -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" bash -s <<REMOTE
set -euo pipefail
AWS_REGION="$AWS_REGION"
ECR_REGISTRY="$ECR_REGISTRY"
ECR_IMAGE="$ECR_IMAGE"
DEPLOY_TAG="$DEPLOY_TAG"
CONTAINER_NAME="$CONTAINER_NAME"
CONTAINER_PORT="$CONTAINER_PORT"

echo "==> Logging into ECR..."
aws ecr get-login-password --region "\$AWS_REGION" | docker login --username AWS --password-stdin "\$ECR_REGISTRY"

echo "==> Stopping old container if exists..."
docker stop "\$CONTAINER_NAME" 2>/dev/null || true
docker rm "\$CONTAINER_NAME" 2>/dev/null || true

echo "==> Pulling image \"\$ECR_IMAGE:\$DEPLOY_TAG\"..."
docker pull "\$ECR_IMAGE:\$DEPLOY_TAG"

echo "==> Starting new container..."
docker run -d \
  --name "\$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "\$CONTAINER_PORT:\$CONTAINER_PORT" \
  "\$ECR_IMAGE:\$DEPLOY_TAG"

echo "==> Verifying container is running..."
docker ps | grep "\$CONTAINER_NAME" || { echo "Container failed to start"; docker logs "\$CONTAINER_NAME" || true; exit 1; }

echo "==> Deployment complete." 
REMOTE

set +x