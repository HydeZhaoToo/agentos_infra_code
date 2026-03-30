# AgentOS 基础设施 Helm 部署设计

## 概述

使用 Helm Umbrella Chart 模式统一管理 AgentOS 基础设施组件的部署，支持 Helm CLI 一键部署和 FluxCD GitOps 两种方式，同集群内通过 namespace 隔离多环境。

## 组件清单

| 组件 | 来源 | 说明 |
|------|------|------|
| litellm | fork 官方 chart | LLM 代理网关 |
| pgsql-relational | fork bitnami/postgresql | 关系数据库（alias 复用 postgresql chart） |
| pgsql-vector | fork bitnami/postgresql | 向量数据库（pgvector 镜像，alias 复用 postgresql chart） |
| obot | fork 官方 chart | AI Agent 平台 |

## 关键决策

1. **Monorepo 单仓管理** — chart 源码、umbrella chart、FluxCD 配置统一在一个仓库
2. **Fork 上游 chart 到本仓** — 通过 git subtree 引入，便于跟踪代码和合并上游更新
3. **保留子依赖，condition 关闭** — fork chart 时不剥离子依赖（如 litellm 内置 postgresql），部署时通过 `postgresql.enabled: false` + `externalDatabase` 指向共享实例，保持与上游最小 diff
4. **Umbrella Chart 统一入口** — `agentos/` 目录作为顶层 chart，通过 `file://` 引用本地子 chart
5. **FluxCD + Kustomize overlay 管理多环境** — base 定义公共 HelmRelease，各环境通过 patch 覆盖 namespace 和 values
6. **PostgreSQL 两实例分离** — 关系数据库和向量数据库使用同一 chart（alias 区分），独立部署

## 仓库结构

```
agentos_infra_code/
│
├── charts/                           # Fork 的上游 chart 源码（git subtree）
│   ├── litellm/
│   │   ├── Chart.yaml
│   │   ├── Chart.lock
│   │   ├── templates/
│   │   └── values.yaml
│   ├── postgresql/
│   │   ├── Chart.yaml
│   │   ├── templates/
│   │   └── values.yaml
│   └── obot/
│       ├── Chart.yaml
│       ├── templates/
│       └── values.yaml
│
├── agentos/                          # Umbrella Chart — 统一部署入口
│   ├── Chart.yaml                    # dependencies 引用 charts/* 子 chart
│   ├── values.yaml                   # 默认配置（全组件开启）
│   ├── values-dev.yaml               # dev 环境覆盖
│   ├── values-staging.yaml           # staging 环境覆盖
│   └── values-production.yaml        # production 环境覆盖
│
├── clusters/                         # FluxCD GitOps 声明
│   └── my-cluster/
│       ├── flux-system/              # FluxCD 自身引导配置
│       │   └── gotk-components.yaml
│       ├── base/                     # 公共 FluxCD 资源
│       │   ├── git-repo.yaml         # GitRepository 指向本仓库
│       │   └── helm-release.yaml     # HelmRelease 模板
│       ├── dev/
│       │   └── kustomization.yaml    # patch namespace + values-dev
│       ├── staging/
│       │   └── kustomization.yaml
│       └── production/
│           └── kustomization.yaml
│
├── scripts/                          # 辅助脚本
│   ├── deploy.sh                     # helm CLI 一键部署
│   └── sync-upstream.sh              # 同步上游 chart 更新
│
└── README.md
```

## Umbrella Chart 设计

### Chart.yaml

```yaml
apiVersion: v2
name: agentos
description: AgentOS 基础设施一键部署
version: 0.1.0
type: application

dependencies:
  - name: litellm
    version: "0.1.0"
    repository: "file://../charts/litellm"
    condition: litellm.enabled

  - name: postgresql
    alias: pgsql-relational
    version: "0.1.0"
    repository: "file://../charts/postgresql"
    condition: pgsql-relational.enabled

  - name: postgresql
    alias: pgsql-vector
    version: "0.1.0"
    repository: "file://../charts/postgresql"
    condition: pgsql-vector.enabled

  - name: obot
    version: "0.1.0"
    repository: "file://../charts/obot"
    condition: obot.enabled
```

### values.yaml（默认值）

```yaml
# ---- litellm ----
litellm:
  enabled: true
  postgresql:
    enabled: false
  externalDatabase:
    host: "agentos-pgsql-relational"
    port: 5432
    database: "litellm"
    existingSecret: "pgsql-relational-credentials"

# ---- PostgreSQL 关系数据库 ----
pgsql-relational:
  enabled: true
  auth:
    postgresPassword: ""
    database: "litellm"
    existingSecret: "pgsql-relational-credentials"
  primary:
    persistence:
      size: 20Gi

# ---- PostgreSQL 向量数据库 ----
pgsql-vector:
  enabled: true
  image:
    repository: pgvector/pgvector
    tag: "pg16"
  auth:
    postgresPassword: ""
    database: "vectors"
    existingSecret: "pgsql-vector-credentials"
  primary:
    persistence:
      size: 20Gi
    initdb:
      scripts:
        enable-pgvector.sql: |
          CREATE EXTENSION IF NOT EXISTS vector;

# ---- obot ----
obot:
  enabled: true
```

### 子依赖复用策略

当子 chart（如 litellm）内置了 postgresql 依赖时：

- **不剥离** — 保留原始 Chart.yaml 中的 dependencies
- **condition 关闭** — 部署时设置 `litellm.postgresql.enabled: false`
- **外部连接** — 配置 `litellm.externalDatabase` 指向共享的 `pgsql-relational` 实例
- **好处** — 与上游 diff 最小，合并更新成本低；独立部署 litellm 时内置 pgsql 仍可用

## 部署方式

### 方式一：Helm CLI

```bash
# 一键部署 dev 环境
helm dependency update ./agentos
helm install agentos ./agentos -f ./agentos/values-dev.yaml -n dev --create-namespace

# 升级
helm upgrade agentos ./agentos -f ./agentos/values-dev.yaml -n dev

# 关闭某个组件
helm upgrade agentos ./agentos -f ./agentos/values-dev.yaml --set obot.enabled=false -n dev

# 使用辅助脚本
./scripts/deploy.sh dev
./scripts/deploy.sh production
```

### 方式二：FluxCD GitOps

FluxCD 通过 `GitRepository` 监听本仓库 main 分支，`HelmRelease` 引用 `./agentos` umbrella chart。

各环境通过 Kustomize overlay 差异化配置：

- `clusters/my-cluster/base/` — 公共 GitRepository + HelmRelease 模板
- `clusters/my-cluster/dev/` — patch namespace=dev, 注入 values-dev
- `clusters/my-cluster/production/` — patch namespace=production, 注入 values-production

**GitOps 工作流**：

```
代码提交 → main 分支 → FluxCD 检测变更(1m 轮询) → helm dependency update → apply HelmRelease → 集群状态与 Git 一致
```

- 更新配置：修改环境 values → push → 自动同步
- 升级 chart：更新 charts/ 下代码 → push → 自动重新部署
- 新增组件：charts/ 加 chart → umbrella 加 dependency → 环境 values 加配置 → push

## FluxCD 配置

### GitRepository

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: agentos-infra
  namespace: flux-system
spec:
  interval: 1m
  url: https://your-git-server.com/agentos_infra_code.git
  ref:
    branch: main
  secretRef:
    name: git-credentials
```

### HelmRelease（base 模板）

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: agentos
spec:
  interval: 5m
  chart:
    spec:
      chart: ./agentos
      sourceRef:
        kind: GitRepository
        name: agentos-infra
        namespace: flux-system
      reconcileStrategy: Revision
  values: {}
```

### 环境 Kustomization（dev 示例）

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base/git-repo.yaml
  - ../base/helm-release.yaml

patches:
  - target:
      kind: HelmRelease
      name: agentos
    patch: |
      - op: replace
        path: /metadata/namespace
        value: dev
      - op: add
        path: /spec/targetNamespace
        value: dev
      - op: add
        path: /spec/install/createNamespace
        value: true
      - op: add
        path: /spec/valuesFrom
        value:
          - kind: ConfigMap
            name: agentos-values-dev

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: agentos-values-dev
  namespace: dev
data:
  values.yaml: |
    pgsql-relational:
      primary:
        persistence:
          size: 5Gi
    pgsql-vector:
      primary:
        persistence:
          size: 5Gi
```

## 上游 Chart 同步

使用 git subtree 管理 fork，通过辅助脚本批量同步：

```bash
# 首次添加
git remote add upstream-postgresql https://github.com/bitnami/charts.git
git subtree add --prefix=charts/postgresql upstream-postgresql main --squash

# 后续同步
./scripts/sync-upstream.sh
```

## 辅助脚本

### deploy.sh

```bash
#!/bin/bash
set -e
ENV="${1:-dev}"
NAMESPACE="${2:-$ENV}"
RELEASE_NAME="${3:-agentos}"

if [ ! -f "./agentos/values-${ENV}.yaml" ]; then
  echo "Error: values-${ENV}.yaml not found"
  exit 1
fi

echo "Deploying AgentOS to namespace: ${NAMESPACE} (env: ${ENV})"
helm dependency update ./agentos
helm upgrade --install "$RELEASE_NAME" ./agentos \
  -f "./agentos/values-${ENV}.yaml" \
  -n "$NAMESPACE" --create-namespace
echo "Done. Check status: helm status ${RELEASE_NAME} -n ${NAMESPACE}"
```

### sync-upstream.sh

```bash
#!/bin/bash
set -e
CHARTS=(
  "litellm|https://github.com/litellm/litellm-helm.git|main"
  "postgresql|https://github.com/bitnami/charts.git|main"
  "obot|https://github.com/obot-platform/obot-helm.git|main"
)

for entry in "${CHARTS[@]}"; do
  IFS='|' read -r name repo branch <<< "$entry"
  echo "Syncing $name from $repo ($branch)..."
  remote_name="upstream-${name}"
  git remote get-url "$remote_name" &>/dev/null || git remote add "$remote_name" "$repo"
  git subtree pull --prefix="charts/${name}" "$remote_name" "$branch" --squash -m "chore: sync upstream ${name}"
done

echo "Done. Run 'helm dependency update ./agentos' to refresh umbrella chart."
```

## 新增组件流程

1. Fork chart 到 `charts/<name>/`（git subtree add）
2. `agentos/Chart.yaml` 添加 dependency 条目
3. `agentos/values.yaml` 添加组件默认配置
4. 各环境 `values-<env>.yaml` 添加环境差异配置
5. 如有子依赖复用，设置 `condition: false` + `externalDatabase` 指向共享实例
6. `scripts/sync-upstream.sh` 添加上游源
7. Push → FluxCD 自动部署 / 或 `./scripts/deploy.sh` 手动部署
