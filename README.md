# AgentOS Infrastructure

AgentOS 基础设施部署仓库 — 基于 Helm Umbrella Chart 统一管理 AI Agent 平台组件，支持 Helm CLI 一键部署和 FluxCD GitOps 持续交付。

## 组件

| 组件 | 说明 | 状态 |
|------|------|------|
| **pgsql-relational** | PostgreSQL 关系数据库（bitnami chart） | ✅ 已实现 |
| **litellm** | LLM API 代理网关 | ✅ 已实现 |
| **pgsql-vector** | PostgreSQL + pgvector 向量数据库 | 🔲 待实现 |
| **obot** | AI Agent 平台 | 🔲 待实现 |

## 仓库结构

```
agentos_infra_code/
├── charts/                  # 上游 Helm Chart 源码（fork）
│   ├── postgresql/          #   bitnami/postgresql
│   └── litellm/             #   litellm 自定义 chart
├── agentos/                 # Umbrella Chart（统一部署入口）
│   ├── Chart.yaml           #   依赖声明
│   ├── values.yaml          #   默认配置
│   ├── values-dev.yaml      #   Dev 环境
│   ├── values-staging.yaml  #   Staging 环境
│   └── values-production.yaml  # Production 环境
├── clusters/                # FluxCD GitOps 配置
│   └── my-cluster/
│       ├── flux-system/     #   FluxCD 引导
│       ├── base/            #   公共资源（GitRepository + HelmRelease）
│       ├── dev/             #   Dev 环境 Kustomization
│       ├── staging/         #   Staging 环境 Kustomization
│       └── production/      #   Production 环境 Kustomization
├── scripts/                 # 辅助脚本
│   ├── deploy.sh            #   Helm CLI 一键部署
│   └── sync-upstream.sh     #   同步上游 Chart 更新
└── docs/
    └── architecture.md      # 架构设计文档
```

## 快速开始

### 前置条件

- [Helm 3](https://helm.sh/docs/intro/install/) 已安装
- kubectl 已配置目标集群
- （可选）[FluxCD CLI](https://fluxcd.io/flux/installation/) 用于 GitOps 模式

### 方式一：Helm CLI 一键部署

```bash
# 部署 dev 环境
./scripts/deploy.sh dev

# 部署 production 环境
./scripts/deploy.sh production

# 自定义 namespace 和 release 名称
./scripts/deploy.sh dev my-namespace my-release

# dry-run 预览（不实际部署）
./scripts/deploy.sh dev dev agentos --dry-run
```

或手动执行：

```bash
# 1. 更新 chart 依赖
helm dependency update ./agentos

# 2. 部署到指定环境
helm install agentos ./agentos \
  -f ./agentos/values-dev.yaml \
  -n dev \
  --create-namespace

# 3. 查看状态
helm status agentos -n dev
kubectl get pods -n dev
```

### 方式二：FluxCD GitOps

```bash
# 1. 引导 FluxCD（首次）
flux bootstrap git \
  --url=https://your-git-server.com/agentos_infra_code.git \
  --branch=main \
  --path=clusters/my-cluster

# 2. 之后所有变更通过 Git 推送自动同步
git push  # FluxCD 自动检测并部署
```

## 环境管理

| 环境 | Namespace | Values 文件 | 说明 |
|------|-----------|-------------|------|
| Dev | `dev` | `values-dev.yaml` | 低资源配额，用于开发调试 |
| Staging | `staging` | `values-staging.yaml` | 中等配额，预发布验证 |
| Production | `production` | `values-production.yaml` | 高可用配置，开启监控 |

同一 K8S 集群内通过 namespace 隔离各环境。

## 常用操作

### 升级组件

```bash
# 修改 values 后升级
helm upgrade agentos ./agentos -f ./agentos/values-dev.yaml -n dev
```

### 开关组件

```bash
# 关闭 litellm
helm upgrade agentos ./agentos \
  -f ./agentos/values-dev.yaml \
  --set litellm.enabled=false \
  -n dev
```

### 同步上游 Chart

```bash
# 同步所有上游 chart
./scripts/sync-upstream.sh

# 只同步 postgresql
./scripts/sync-upstream.sh postgresql

# 同步后重新构建依赖
helm dependency update ./agentos
```

### 查看部署状态

```bash
helm status agentos -n dev
kubectl get pods -n dev
kubectl logs -n dev deploy/agentos-litellm
```

## CI/CD

### CI — 自动验证（GitHub Actions）

每次 PR 或 push 到 main 时自动运行：

- Helm lint（所有子 chart + umbrella chart）
- Template dry-run（dev/staging/production 三个环境）
- 组件开关验证

配置文件：`.github/workflows/ci.yaml`

### CD — FluxCD 自动部署

采用 **轮询 + Push 触发** 双机制：

| 机制 | 触发方式 | 延迟 | 说明 |
|------|----------|------|------|
| 轮询 | FluxCD 每 1m 检查 Git | ~1min | 兜底，确保最终一致性 |
| Push 触发 | GitHub Actions webhook | ~秒级 | 加速部署，push 后立即 reconcile |

启用 Push 触发需要：

1. 在 K8S 集群部署 FluxCD Receiver（见 `clusters/my-cluster/base/receiver.yaml`）
2. 获取 webhook URL：`kubectl get receiver github-push -n flux-system`
3. 在 GitHub repo Settings > Secrets 添加：
   - `FLUXCD_WEBHOOK_URL` — Receiver webhook 完整 URL
   - `FLUXCD_WEBHOOK_TOKEN` — webhook 验证 token

配置文件：`.github/workflows/cd-notify-fluxcd.yaml`

## 新增组件指南

详见 [架构文档](docs/architecture.md) 中的"新增组件流程"章节。

## Secrets 管理

本仓库 **不存储任何密码或密钥**。部署前需在目标 namespace 创建 Secret：

```bash
# PostgreSQL 凭据
kubectl create secret generic pgsql-relational-credentials \
  --from-literal=postgres-password='YOUR_PASSWORD' \
  -n dev

# LiteLLM Master Key（可选）
kubectl create secret generic litellm-secret \
  --from-literal=master-key='YOUR_MASTER_KEY' \
  -n dev
```

## 相关文档

- [架构设计文档](docs/architecture.md) — 整体架构、设计决策、组件关系
- [设计 Spec](docs/superpowers/specs/2026-03-29-agentos-infra-helm-design.md) — 原始设计讨论记录
