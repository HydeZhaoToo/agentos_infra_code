#!/bin/bash
set -e

# 同步上游 Helm Chart 到 charts/ 目录
# 用法: ./scripts/sync-upstream.sh [chart名称]
# 示例:
#   ./scripts/sync-upstream.sh              # 同步全部
#   ./scripts/sync-upstream.sh postgresql   # 只同步 postgresql

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CHARTS_DIR="${PROJECT_DIR}/charts"

# 上游 chart 配置: name|repo|chart|version
UPSTREAM_CHARTS=(
  "postgresql|bitnami|bitnami/postgresql|16.4.1"
  # litellm 暂无官方 helm repo，使用自定义 chart
  # "litellm|litellm|litellm/litellm|"
)

# Helm repos（确保已添加）
ensure_repos() {
  echo "Ensuring Helm repos..."
  helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
  helm repo update
}

sync_chart() {
  local name="$1" repo="$2" chart="$3" version="$4"
  local target="${CHARTS_DIR}/${name}"

  echo ""
  echo "Syncing ${name}..."

  if [ -n "$version" ]; then
    echo "  Pulling ${chart} version ${version}"
    rm -rf "$target"
    helm pull "$chart" --version "$version" --untar --untardir "$CHARTS_DIR"
  else
    echo "  Pulling ${chart} (latest)"
    rm -rf "$target"
    helm pull "$chart" --untar --untardir "$CHARTS_DIR"
  fi

  if [ -d "$target" ]; then
    echo "  OK: ${target}"
  else
    echo "  WARNING: Expected directory ${target} not found. Chart name may differ."
    echo "  Check ${CHARTS_DIR}/ and rename if needed."
  fi
}

# 主逻辑
FILTER="${1:-}"
ensure_repos

for entry in "${UPSTREAM_CHARTS[@]}"; do
  IFS='|' read -r name repo chart version <<< "$entry"
  if [ -z "$FILTER" ] || [ "$FILTER" = "$name" ]; then
    sync_chart "$name" "$repo" "$chart" "$version"
  fi
done

echo ""
echo "======================================"
echo " Sync complete!"
echo " Next: helm dependency update ${PROJECT_DIR}/agentos"
echo "======================================"
