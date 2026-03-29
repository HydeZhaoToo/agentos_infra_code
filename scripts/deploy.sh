#!/bin/bash
set -e

# AgentOS 一键部署脚本
# 用法: ./scripts/deploy.sh [环境] [namespace] [release名称]
# 示例:
#   ./scripts/deploy.sh dev
#   ./scripts/deploy.sh production prod agentos
#   ./scripts/deploy.sh dev dev agentos --dry-run

ENV="${1:-dev}"
NAMESPACE="${2:-$ENV}"
RELEASE_NAME="${3:-agentos}"
shift 3 2>/dev/null || true
EXTRA_ARGS="$@"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CHART_DIR="${PROJECT_DIR}/agentos"
VALUES_FILE="${CHART_DIR}/values-${ENV}.yaml"

if [ ! -f "$VALUES_FILE" ]; then
  echo "Error: ${VALUES_FILE} not found"
  echo "Available environments:"
  ls "${CHART_DIR}"/values-*.yaml 2>/dev/null | sed 's/.*values-//;s/.yaml//'
  exit 1
fi

echo "======================================"
echo " AgentOS Deployment"
echo " Environment: ${ENV}"
echo " Namespace:   ${NAMESPACE}"
echo " Release:     ${RELEASE_NAME}"
echo "======================================"

echo ""
echo "[1/2] Updating Helm dependencies..."
helm dependency update "$CHART_DIR"

echo ""
echo "[2/2] Deploying..."
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  -f "$VALUES_FILE" \
  -n "$NAMESPACE" \
  --create-namespace \
  $EXTRA_ARGS

echo ""
echo "======================================"
echo " Deployment complete!"
echo " Check status: helm status ${RELEASE_NAME} -n ${NAMESPACE}"
echo " List pods:    kubectl get pods -n ${NAMESPACE}"
echo "======================================"
