# AgentOS 基础设施架构文档

## 1. 概述

AgentOS 基础设施代码仓库采用 **Helm Umbrella Chart** 模式，将多个松耦合的 AI Agent 平台组件统一编排部署到 Kubernetes 集群。

### 设计目标

1. **统一部署** — 一条命令部署整个平台栈
2. **独立管控** — 每个组件可独立开启/关闭/升级
3. **多环境支持** — 同集群内 dev/staging/production namespace 隔离
4. **双模式交付** — 支持 Helm CLI 手动部署和 FluxCD GitOps 自动交付
5. **代码可追踪** — 上游 Chart 源码 fork 到本仓库，版本可控

## 2. 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                     Git Repository                          │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ charts/      │  │ agentos/     │  │ clusters/        │  │
│  │  postgresql/ │  │  Chart.yaml  │  │  my-cluster/     │  │
│  │  litellm/    │  │  values*.yaml│  │   base/          │  │
│  │  (obot/)     │  │              │  │   dev/staging/   │  │
│  │              │  │  Umbrella    │  │   production/    │  │
│  │  Fork 源码   │  │  Chart       │  │  FluxCD 配置     │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                    │            │
└─────────┼─────────────────┼────────────────────┼────────────┘
          │                 │                    │
          │    ┌────────────┘                    │
          │    │  file:// 引用                   │  GitOps
          │    │                                 │
          ▼    ▼                                 ▼
┌──────────────────┐                 ┌──────────────────────┐
│   Helm CLI       │                 │   FluxCD             │
│                  │                 │   GitRepository      │
│  helm install    │                 │   HelmRelease        │
│  helm upgrade    │                 │   Kustomize Overlay  │
└────────┬─────────┘                 └──────────┬───────────┘
         │                                      │
         └──────────────┬───────────────────────┘
                        │
                        ▼
         ┌──────────────────────────┐
         │     Kubernetes Cluster   │
         │                          │
         │  ┌────────┐ ┌────────┐  │
         │  │  dev   │ │staging │  │
         │  │namespace│ │namespace│ │
         │  └────────┘ └────────┘  │
         │  ┌────────────────────┐ │
         │  │   production      │  │
         │  │   namespace       │  │
         │  └────────────────────┘ │
         └──────────────────────────┘
```

## 3. 组件关系

```
                    ┌──────────────────┐
                    │  agentos         │
                    │  (Umbrella Chart)│
                    └─────┬────────────┘
                          │
            ┌─────────────┼─────────────────┐
            │             │                 │
            ▼             ▼                 ▼
     ┌────────────┐ ┌──────────┐    ┌─────────────┐
     │ litellm    │ │ pgsql-   │    │  (其他组件)  │
     │            │ │ relational│   │  pgsql-vector│
     │ LLM Gateway│ │          │    │  obot        │
     └─────┬──────┘ │PostgreSQL│    │  ...         │
           │        └──────────┘    └──────────────┘
           │             ▲
           │             │
           └─────────────┘
        externalDatabase 连接
```

- **litellm** 依赖 **pgsql-relational** 作为其后端数据库
- litellm chart 内置的 postgresql 子依赖通过 `postgresql.enabled: false` 关闭
- 通过 `externalDatabase` 配置指向共享的 pgsql-relational 实例
- 各组件通过 `<组件>.enabled` 独立控制开关

## 4. 关键设计决策

### 4.1 Monorepo 单仓管理

**决策：** Chart 源码、Umbrella Chart、FluxCD 配置统一在一个仓库。

**原因：**
- 3-4 个组件规模适中，无需多仓
- 变更原子性 — Chart 修改和 GitOps 配置在同一次提交
- 降低管理成本

### 4.2 Fork 上游 Chart 源码

**决策：** 上游 Chart 通过 `helm pull` 获取指定版本，放入 `charts/` 目录。

**原因：**
- 需要完全掌控 Chart 代码，可自由修改
- 可追踪变更历史
- 不依赖外部 Helm Repo 可用性

**升级方式：** `scripts/sync-upstream.sh` 拉取新版本覆盖，通过 git diff 审查变更。

### 4.3 保留子依赖 + Condition 关闭

**决策：** Fork Chart 时保留原始 dependencies（如 litellm 内置的 postgresql），部署时通过 condition 关闭。

**原因：**
- 与上游 diff 最小，合并更新成本低
- 独立部署某个 Chart 时子依赖仍可用
- Helm 社区标准做法

**具体操作：**
```yaml
# Umbrella values.yaml
litellm:
  postgresql:
    enabled: false        # 关闭内置 postgresql
  externalDatabase:
    host: "agentos-pgsql-relational"  # 指向共享实例
```

### 4.4 多环境 Namespace 隔离

**决策：** 同一 K8S 集群内，通过 namespace 隔离 dev/staging/production。

**实现：**
- Helm CLI：`-n <namespace>` 参数
- FluxCD：Kustomize patch `targetNamespace`

### 4.5 双模式交付

**决策：** 同时支持 Helm CLI 手动部署和 FluxCD GitOps。

**Helm CLI 场景：** 快速调试、本地开发、初始部署、紧急修复。

**FluxCD 场景：** 持续交付、自动同步、生产环境日常运维。

两种方式使用同一套 Chart 和 Values，保证一致性。

## 5. 数据流

### 5.1 Helm CLI 部署流程

```
开发者修改 values
    │
    ▼
helm dependency update ./agentos    ← 拉取子 chart 到 agentos/charts/
    │
    ▼
helm upgrade --install agentos ./agentos -f values-<env>.yaml -n <ns>
    │
    ▼
Kubernetes API Server
    │
    ▼
Pod/Service/PVC 等资源创建或更新
```

### 5.2 FluxCD GitOps 流程

```
开发者 push 到 main 分支
    │
    ▼
FluxCD GitRepository (1m 轮询)
    │  检测到新 commit
    ▼
FluxCD Kustomize Controller
    │  渲染 clusters/my-cluster/<env>/kustomization.yaml
    ▼
FluxCD Helm Controller
    │  执行 helm upgrade --install
    ▼
Kubernetes API Server
    │
    ▼
集群状态与 Git 仓库保持一致
```

## 6. Secrets 管理

**原则：** 仓库中不存储任何密码或密钥。

**方式：** 使用 Kubernetes Secret + `existingSecret` 引用。

部署前需在目标 namespace 创建：

```bash
# PostgreSQL 凭据
kubectl create secret generic pgsql-relational-credentials \
  --from-literal=postgres-password='<password>' \
  -n <namespace>

# LiteLLM Master Key（可选）
kubectl create secret generic litellm-secret \
  --from-literal=master-key='<key>' \
  -n <namespace>
```

生产环境建议使用 Sealed Secrets 或 External Secrets Operator 进行自动化管理。

## 7. 新增组件流程

当需要新增一个组件（如 obot、pgsql-vector）时，按以下步骤操作：

### Step 1: 引入 Chart

```bash
# 如果上游有 Helm Repo
helm pull <repo>/<chart> --version <ver> --untar --untardir charts/

# 在 sync-upstream.sh 中添加条目
# "name|repo_name|repo/chart|version"
```

### Step 2: 更新 Umbrella Chart

在 `agentos/Chart.yaml` 中添加依赖：

```yaml
dependencies:
  # ... 已有依赖 ...
  - name: <chart-name>
    alias: <alias>              # 如需复用同一 chart
    version: "<version>"
    repository: "file://../charts/<chart-name>"
    condition: <alias>.enabled
```

### Step 3: 添加默认配置

在 `agentos/values.yaml` 中添加：

```yaml
<alias>:
  enabled: true
  # ... 组件配置 ...
```

### Step 4: 各环境差异配置

在 `values-dev.yaml`、`values-staging.yaml`、`values-production.yaml` 中添加环境差异。

### Step 5: 更新 FluxCD ConfigMap

在 `clusters/my-cluster/<env>/kustomization.yaml` 的 ConfigMap 中添加对应配置。

### Step 6: 处理子依赖复用

如果新组件内置了已有组件的子依赖（如内置 postgresql）：

1. 保留原始子依赖不删除
2. 在 values 中关闭：`<component>.postgresql.enabled: false`
3. 配置外部连接：`<component>.externalDatabase.host: "agentos-pgsql-relational"`

### Step 7: 验证并提交

```bash
helm dependency update ./agentos
helm lint ./agentos
helm template agentos ./agentos -f ./agentos/values-dev.yaml -n dev > /dev/null
git add -A && git commit -m "feat: add <component> to agentos umbrella chart"
```

## 8. 上游 Chart 升级流程

```bash
# 1. 运行同步脚本
./scripts/sync-upstream.sh postgresql

# 2. 审查变更
git diff charts/postgresql/

# 3. 更新 Umbrella Chart 版本号（如果上游 chart version 变了）
# 编辑 agentos/Chart.yaml 中对应 dependency 的 version 字段

# 4. 验证
helm dependency update ./agentos
helm lint ./agentos
helm template agentos ./agentos -f ./agentos/values-dev.yaml > /dev/null

# 5. 提交
git add -A && git commit -m "chore: upgrade postgresql chart to vX.Y.Z"
```
