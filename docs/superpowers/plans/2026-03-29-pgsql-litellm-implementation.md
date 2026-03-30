# PostgreSQL + LiteLLM 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地 pgsql-relational 和 litellm 两个组件的 Helm Chart，构建 Umbrella Chart 支持一键部署和 FluxCD GitOps，并编写完整的 README、架构文档和使用指南。

**Architecture:** Monorepo 中 `charts/` 存放 fork 的上游 chart 源码，`agentos/` 作为 Umbrella Chart 通过 `file://` 引用子 chart。`clusters/` 存放 FluxCD GitOps 声明。obot 和 pgsql-vector 暂不实现（由其他同事负责），但 Umbrella Chart 预留 `enabled: false` 占位。

**Tech Stack:** Helm 3, FluxCD v2, Kustomize, PostgreSQL (bitnami chart), LiteLLM (官方 chart), Git Subtree

**范围说明：** 本计划仅实现 pgsql-relational 和 litellm。obot 与 pgsql-vector 由其他同事负责，umbrella chart 中以 `enabled: false` 预留。

---

## 文件结构总览

```
agentos_infra_code/
├── .gitignore
├── README.md                                    # 项目总入口文档
├── docs/
│   └── architecture.md                          # 架构设计文档
├── charts/
│   ├── postgresql/                              # git subtree fork bitnami/postgresql
│   └── litellm/                                 # git subtree fork litellm 官方 chart
├── agentos/
│   ├── Chart.yaml                               # Umbrella Chart 依赖声明
│   ├── values.yaml                              # 默认 values（全局）
│   ├── values-dev.yaml                          # dev 环境覆盖
│   ├── values-staging.yaml                      # staging 环境覆盖
│   └── values-production.yaml                   # production 环境覆盖
├── clusters/
│   └── my-cluster/
│       ├── flux-system/
│       │   └── gotk-components.yaml             # FluxCD 引导（占位）
│       ├── base/
│       │   ├── git-repo.yaml                    # GitRepository 资源
│       │   └── helm-release.yaml                # HelmRelease 模板
│       ├── dev/
│       │   └── kustomization.yaml
│       ├── staging/
│       │   └── kustomization.yaml
│       └── production/
│           └── kustomization.yaml
├── scripts/
│   ├── deploy.sh                                # Helm CLI 一键部署
│   └── sync-upstream.sh                         # 同步上游 chart
└── docs/
    └── architecture.md                          # 架构文档
```

---

### Task 1: 初始化 Git 仓库和基础结构

**Files:**
- Create: `.gitignore`
- Create: 目录结构骨架

- [ ] **Step 1: 初始化 git 仓库**

```bash
cd /Users/zzzhao/project/benz/RD/agentos_infra_code
git init
```

- [ ] **Step 2: 创建 .gitignore**

```gitignore
# Helm
charts/*/charts/
charts/*/tmpcharts/
agentos/charts/
agentos/tmpcharts/
Chart.lock

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Secrets - 绝对不要提交
**/secrets/
*.key
*.pem
```

- [ ] **Step 3: 创建目录骨架**

```bash
mkdir -p charts/postgresql
mkdir -p charts/litellm
mkdir -p agentos
mkdir -p clusters/my-cluster/{flux-system,base,dev,staging,production}
mkdir -p scripts
mkdir -p docs
```

- [ ] **Step 4: 提交**

```bash
git add .gitignore
git commit -m "chore: init repo with .gitignore"
```

---

### Task 2: 引入 PostgreSQL Chart（git subtree）

**Files:**
- Create: `charts/postgresql/` (来自 bitnami 上游)

- [ ] **Step 1: 添加 bitnami 远程并引入 postgresql chart**

bitnami/charts 仓库结构为 `bitnami/postgresql/`，需要引入指定子目录。由于 git subtree 不支持子目录，采用替代方案：手动下载指定版本的 chart 并放入 `charts/postgresql/`。

```bash
# 方案：使用 helm pull 获取指定版本 chart 包并解压
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm pull bitnami/postgresql --version 16.4.1 --untar --untardir charts/
```

这会在 `charts/postgresql/` 下生成完整的 chart 源码。

> **备注：** bitnami/charts 是一个大型 monorepo，git subtree 引入整个仓库不实际。使用 `helm pull` 获取特定版本的 chart 更高效。后续升级通过 `helm pull` 新版本覆盖即可。`scripts/sync-upstream.sh` 将使用此方式。

- [ ] **Step 2: 验证 chart 结构**

```bash
ls charts/postgresql/
# 预期输出包含: Chart.yaml  templates/  values.yaml  README.md
helm lint charts/postgresql/
# 预期: 0 error(s)
```

- [ ] **Step 3: 提交**

```bash
git add charts/postgresql/
git commit -m "feat: add bitnami/postgresql chart v16.4.1"
```

---

### Task 3: 引入 LiteLLM Chart

**Files:**
- Create: `charts/litellm/` (来自 litellm 上游)

- [ ] **Step 1: 获取 litellm helm chart**

```bash
# 先检查 litellm 是否有官方 helm repo
helm repo add litellm https://litellm.github.io/helm-chart 2>/dev/null

# 如果有官方 repo：
helm repo update
helm pull litellm/litellm --untar --untardir charts/

# 如果没有官方 helm repo，从 GitHub releases 或源码获取：
# git clone --depth 1 https://github.com/BerriAI/litellm.git /tmp/litellm-src
# cp -r /tmp/litellm-src/deploy/charts/litellm charts/litellm
# rm -rf /tmp/litellm-src
```

> **备注：** LiteLLM 的 Helm chart 分发方式可能变化，执行时需确认实际可用的获取方式。如果上游没有 chart，需要自行编写（见 Task 3b 备选方案）。

- [ ] **Step 2: 验证 chart 结构**

```bash
ls charts/litellm/
# 预期: Chart.yaml  templates/  values.yaml
helm lint charts/litellm/
# 预期: 0 error(s)
```

- [ ] **Step 3: 检查 litellm chart 是否内置 postgresql 依赖**

```bash
cat charts/litellm/Chart.yaml | grep -A 5 "dependencies"
# 如果包含 postgresql 依赖，记录下来 — umbrella chart 需要通过 condition 关闭它
```

- [ ] **Step 4: 提交**

```bash
git add charts/litellm/
git commit -m "feat: add litellm helm chart"
```

---

### Task 3b（备选）: 如果 LiteLLM 没有官方 Chart，手动编写

**仅在 Task 3 Step 1 无法获取官方 chart 时执行此任务。**

**Files:**
- Create: `charts/litellm/Chart.yaml`
- Create: `charts/litellm/values.yaml`
- Create: `charts/litellm/templates/deployment.yaml`
- Create: `charts/litellm/templates/service.yaml`
- Create: `charts/litellm/templates/configmap.yaml`
- Create: `charts/litellm/templates/secret.yaml`
- Create: `charts/litellm/templates/_helpers.tpl`
- Create: `charts/litellm/templates/NOTES.txt`

- [ ] **Step 1: 创建 Chart.yaml**

```yaml
apiVersion: v2
name: litellm
description: LiteLLM Proxy - LLM API Gateway
type: application
version: 0.1.0
appVersion: "1.61.0"
```

- [ ] **Step 2: 创建 values.yaml**

```yaml
replicaCount: 1

image:
  repository: ghcr.io/berriai/litellm
  tag: "main-latest"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 4000

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

# 内置 postgresql（umbrella 部署时关闭）
postgresql:
  enabled: true
  auth:
    database: litellm
    existingSecret: ""

# 外部数据库配置（postgresql.enabled=false 时生效）
externalDatabase:
  host: ""
  port: 5432
  database: "litellm"
  existingSecret: ""
  existingSecretPasswordKey: "postgres-password"

# LiteLLM 配置
masterKey: ""
existingSecret: ""

config: {}
#  model_list:
#    - model_name: gpt-4
#      litellm_params:
#        model: openai/gpt-4
#        api_key: os.environ/OPENAI_API_KEY

env: []

ingress:
  enabled: false
  className: ""
  hosts: []
  tls: []
```

- [ ] **Step 3: 创建 templates/_helpers.tpl**

```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "litellm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "litellm.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "litellm.labels" -}}
helm.sh/chart: {{ include "litellm.chart" . }}
{{ include "litellm.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "litellm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "litellm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "litellm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Database URL — 根据 postgresql.enabled 决定使用内置或外部数据库
*/}}
{{- define "litellm.databaseUrl" -}}
{{- if .Values.postgresql.enabled }}
{{- printf "postgresql://postgres:$(DATABASE_PASSWORD)@%s-postgresql:5432/%s" (include "litellm.fullname" .) .Values.postgresql.auth.database }}
{{- else }}
{{- printf "postgresql://postgres:$(DATABASE_PASSWORD)@%s:%v/%s" .Values.externalDatabase.host (int .Values.externalDatabase.port) .Values.externalDatabase.database }}
{{- end }}
{{- end }}

{{/*
Database secret name
*/}}
{{- define "litellm.databaseSecretName" -}}
{{- if .Values.postgresql.enabled }}
{{- if .Values.postgresql.auth.existingSecret }}
{{- .Values.postgresql.auth.existingSecret }}
{{- else }}
{{- printf "%s-postgresql" (include "litellm.fullname" .) }}
{{- end }}
{{- else }}
{{- .Values.externalDatabase.existingSecret }}
{{- end }}
{{- end }}
```

- [ ] **Step 4: 创建 templates/configmap.yaml**

```yaml
{{- if .Values.config }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "litellm.fullname" . }}-config
  labels:
    {{- include "litellm.labels" . | nindent 4 }}
data:
  config.yaml: |
    {{- toYaml .Values.config | nindent 4 }}
{{- end }}
```

- [ ] **Step 5: 创建 templates/deployment.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "litellm.fullname" . }}
  labels:
    {{- include "litellm.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "litellm.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "litellm.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 4000
              protocol: TCP
          env:
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "litellm.databaseSecretName" . }}
                  key: {{ .Values.externalDatabase.existingSecretPasswordKey | default "postgres-password" }}
            - name: DATABASE_URL
              value: {{ include "litellm.databaseUrl" . | quote }}
            {{- if .Values.masterKey }}
            - name: LITELLM_MASTER_KEY
              value: {{ .Values.masterKey | quote }}
            {{- else if .Values.existingSecret }}
            - name: LITELLM_MASTER_KEY
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.existingSecret }}
                  key: master-key
            {{- end }}
            {{- with .Values.env }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- if .Values.config }}
          args:
            - "--config"
            - "/etc/litellm/config.yaml"
          volumeMounts:
            - name: config
              mountPath: /etc/litellm
              readOnly: true
          {{- end }}
          livenessProbe:
            httpGet:
              path: /health/liveliness
              port: http
            initialDelaySeconds: 15
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health/readiness
              port: http
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
      {{- if .Values.config }}
      volumes:
        - name: config
          configMap:
            name: {{ include "litellm.fullname" . }}-config
      {{- end }}
```

- [ ] **Step 6: 创建 templates/service.yaml**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "litellm.fullname" . }}
  labels:
    {{- include "litellm.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "litellm.selectorLabels" . | nindent 4 }}
```

- [ ] **Step 7: 创建 templates/NOTES.txt**

```
LiteLLM Proxy has been deployed.

Get the application URL:
{{- if contains "NodePort" .Values.service.type }}
  export NODE_PORT=$(kubectl get --namespace {{ .Release.Namespace }} -o jsonpath="{.spec.ports[0].nodePort}" services {{ include "litellm.fullname" . }})
  export NODE_IP=$(kubectl get nodes --namespace {{ .Release.Namespace }} -o jsonpath="{.items[0].status.addresses[0].address}")
  echo http://$NODE_IP:$NODE_PORT
{{- else if contains "ClusterIP" .Values.service.type }}
  kubectl --namespace {{ .Release.Namespace }} port-forward svc/{{ include "litellm.fullname" . }} {{ .Values.service.port }}:{{ .Values.service.port }}
  echo http://127.0.0.1:{{ .Values.service.port }}
{{- end }}
```

- [ ] **Step 8: lint 验证**

```bash
helm lint charts/litellm/
# 预期: 0 error(s)
```

- [ ] **Step 9: 提交**

```bash
git add charts/litellm/
git commit -m "feat: add litellm helm chart (custom)"
```

---

### Task 4: 创建 Umbrella Chart

**Files:**
- Create: `agentos/Chart.yaml`
- Create: `agentos/values.yaml`
- Create: `agentos/values-dev.yaml`
- Create: `agentos/values-staging.yaml`
- Create: `agentos/values-production.yaml`

- [ ] **Step 1: 创建 agentos/Chart.yaml**

```yaml
apiVersion: v2
name: agentos
description: AgentOS Infrastructure - Unified Deployment Chart
version: 0.1.0
type: application

dependencies:
  # ---- 本次实现 ----
  - name: litellm
    version: "0.1.0"
    repository: "file://../charts/litellm"
    condition: litellm.enabled

  - name: postgresql
    alias: pgsql-relational
    version: "16.4.1"
    repository: "file://../charts/postgresql"
    condition: pgsql-relational.enabled

  # ---- 以下由其他同事实现，暂 disabled ----
  # - name: postgresql
  #   alias: pgsql-vector
  #   version: "16.4.1"
  #   repository: "file://../charts/postgresql"
  #   condition: pgsql-vector.enabled

  # - name: obot
  #   version: "0.1.0"
  #   repository: "file://../charts/obot"
  #   condition: obot.enabled
```

> **注意：** `version` 字段需与 `charts/postgresql/Chart.yaml` 和 `charts/litellm/Chart.yaml` 中的 `version` 一致。执行时请检查实际版本号并对齐。

- [ ] **Step 2: 创建 agentos/values.yaml**

```yaml
# =============================================================================
# AgentOS Umbrella Chart - 默认配置
# =============================================================================

# ---- LiteLLM ----
litellm:
  enabled: true

  # 关闭内置 postgresql，使用共享的 pgsql-relational
  postgresql:
    enabled: false

  externalDatabase:
    host: "agentos-pgsql-relational"
    port: 5432
    database: "litellm"
    existingSecret: "pgsql-relational-credentials"
    existingSecretPasswordKey: "postgres-password"

  replicaCount: 1

  image:
    repository: ghcr.io/berriai/litellm
    tag: "main-latest"
    pullPolicy: IfNotPresent

  service:
    type: ClusterIP
    port: 4000

  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: "1"
      memory: 1Gi

  # LiteLLM 模型配置 - 按需覆盖
  config: {}

# ---- PostgreSQL 关系数据库 ----
pgsql-relational:
  enabled: true

  auth:
    postgresPassword: ""
    database: "litellm"
    existingSecret: "pgsql-relational-credentials"

  primary:
    persistence:
      enabled: true
      size: 20Gi
    resources:
      requests:
        cpu: 250m
        memory: 512Mi
      limits:
        cpu: "1"
        memory: 1Gi

# ---- PostgreSQL 向量数据库（暂未实现）----
# pgsql-vector:
#   enabled: false

# ---- obot（暂未实现）----
# obot:
#   enabled: false
```

- [ ] **Step 3: 创建 agentos/values-dev.yaml**

```yaml
# =============================================================================
# AgentOS - Dev 环境配置
# =============================================================================

litellm:
  replicaCount: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

pgsql-relational:
  primary:
    persistence:
      size: 5Gi
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

- [ ] **Step 4: 创建 agentos/values-staging.yaml**

```yaml
# =============================================================================
# AgentOS - Staging 环境配置
# =============================================================================

litellm:
  replicaCount: 2
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: "1"
      memory: 1Gi

pgsql-relational:
  primary:
    persistence:
      size: 10Gi
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: "1"
        memory: 1Gi
```

- [ ] **Step 5: 创建 agentos/values-production.yaml**

```yaml
# =============================================================================
# AgentOS - Production 环境配置
# =============================================================================

litellm:
  replicaCount: 3
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: "2"
      memory: 2Gi

pgsql-relational:
  primary:
    persistence:
      size: 50Gi
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: "2"
        memory: 2Gi
  # Production 建议开启指标监控
  metrics:
    enabled: true
```

- [ ] **Step 6: 构建依赖并验证**

```bash
helm dependency update ./agentos
helm lint ./agentos
# 预期: 0 error(s)

# dry-run 验证渲染结果
helm template agentos ./agentos -f ./agentos/values-dev.yaml -n dev > /dev/null
echo "Template render: OK"
```

- [ ] **Step 7: 提交**

```bash
git add agentos/
git commit -m "feat: add agentos umbrella chart with pgsql-relational and litellm"
```

---

### Task 5: 创建 FluxCD GitOps 配置

**Files:**
- Create: `clusters/my-cluster/flux-system/gotk-components.yaml`
- Create: `clusters/my-cluster/base/git-repo.yaml`
- Create: `clusters/my-cluster/base/helm-release.yaml`
- Create: `clusters/my-cluster/dev/kustomization.yaml`
- Create: `clusters/my-cluster/staging/kustomization.yaml`
- Create: `clusters/my-cluster/production/kustomization.yaml`

- [ ] **Step 1: 创建 flux-system 占位**

```yaml
# clusters/my-cluster/flux-system/gotk-components.yaml
# FluxCD 组件由 `flux bootstrap` 命令自动生成
# 此文件为占位，实际使用时运行：
#   flux bootstrap git \
#     --url=https://your-git-server.com/agentos_infra_code.git \
#     --branch=main \
#     --path=clusters/my-cluster
```

- [ ] **Step 2: 创建 base/git-repo.yaml**

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

- [ ] **Step 3: 创建 base/helm-release.yaml**

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: agentos
  namespace: flux-system
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

- [ ] **Step 4: 创建 dev/kustomization.yaml**

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
        path: /spec/install
        value:
          createNamespace: true
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
    litellm:
      replicaCount: 1
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 500m
          memory: 512Mi
    pgsql-relational:
      primary:
        persistence:
          size: 5Gi
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

- [ ] **Step 5: 创建 staging/kustomization.yaml**

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
        value: staging
      - op: add
        path: /spec/targetNamespace
        value: staging
      - op: add
        path: /spec/install
        value:
          createNamespace: true
      - op: add
        path: /spec/valuesFrom
        value:
          - kind: ConfigMap
            name: agentos-values-staging

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: agentos-values-staging
  namespace: staging
data:
  values.yaml: |
    litellm:
      replicaCount: 2
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: "1"
          memory: 1Gi
    pgsql-relational:
      primary:
        persistence:
          size: 10Gi
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: "1"
            memory: 1Gi
```

- [ ] **Step 6: 创建 production/kustomization.yaml**

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
        value: production
      - op: add
        path: /spec/targetNamespace
        value: production
      - op: add
        path: /spec/install
        value:
          createNamespace: true
      - op: add
        path: /spec/valuesFrom
        value:
          - kind: ConfigMap
            name: agentos-values-production

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: agentos-values-production
  namespace: production
data:
  values.yaml: |
    litellm:
      replicaCount: 3
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: "2"
          memory: 2Gi
    pgsql-relational:
      primary:
        persistence:
          size: 50Gi
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: "2"
            memory: 2Gi
      metrics:
        enabled: true
```

- [ ] **Step 7: 提交**

```bash
git add clusters/
git commit -m "feat: add FluxCD GitOps configuration for dev/staging/production"
```

---

### Task 6: 创建辅助脚本

**Files:**
- Create: `scripts/deploy.sh`
- Create: `scripts/sync-upstream.sh`

- [ ] **Step 1: 创建 scripts/deploy.sh**

```bash
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
```

- [ ] **Step 2: 创建 scripts/sync-upstream.sh**

```bash
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
  "litellm|litellm|litellm/litellm|"
)

# Helm repos（确保已添加）
ensure_repos() {
  echo "Ensuring Helm repos..."
  helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
  # 如果 litellm 有官方 repo，取消下面的注释：
  # helm repo add litellm https://litellm.github.io/helm-chart 2>/dev/null || true
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
```

- [ ] **Step 3: 设置脚本可执行权限**

```bash
chmod +x scripts/deploy.sh scripts/sync-upstream.sh
```

- [ ] **Step 4: 提交**

```bash
git add scripts/
git commit -m "feat: add deploy and sync-upstream helper scripts"
```

---

### Task 7: 编写 README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: 创建 README.md**

```markdown
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
│   └── litellm/             #   litellm 官方 / 自定义
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
```

- [ ] **Step 2: 提交**

```bash
git add README.md
git commit -m "docs: add comprehensive README with quickstart and usage guide"
```

---

### Task 8: 编写架构文档

**Files:**
- Create: `docs/architecture.md`

- [ ] **Step 1: 创建 docs/architecture.md**

```markdown
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
```

- [ ] **Step 2: 提交**

```bash
git add docs/architecture.md
git commit -m "docs: add architecture document with design decisions and workflows"
```

---

### Task 9: 最终验证

- [ ] **Step 1: 验证完整目录结构**

```bash
find . -not -path './.git/*' -not -path './.idea/*' -not -path './.claude/*' -not -path './docs/superpowers/*' | sort
```

预期输出包含所有必要文件。

- [ ] **Step 2: Helm lint 全部通过**

```bash
helm lint charts/postgresql/
helm lint charts/litellm/
helm dependency update ./agentos
helm lint ./agentos
```

预期：全部 0 error(s)。

- [ ] **Step 3: Template dry-run 各环境**

```bash
helm template agentos ./agentos -f ./agentos/values-dev.yaml -n dev > /dev/null && echo "dev: OK"
helm template agentos ./agentos -f ./agentos/values-staging.yaml -n staging > /dev/null && echo "staging: OK"
helm template agentos ./agentos -f ./agentos/values-production.yaml -n production > /dev/null && echo "production: OK"
```

- [ ] **Step 4: 验证组件开关**

```bash
# 关闭 litellm，只部署 pgsql
helm template agentos ./agentos \
  -f ./agentos/values-dev.yaml \
  --set litellm.enabled=false \
  -n dev | grep "kind:" | sort | uniq -c
# 预期：不出现 litellm 相关资源

# 关闭 pgsql，只部署 litellm
helm template agentos ./agentos \
  -f ./agentos/values-dev.yaml \
  --set pgsql-relational.enabled=false \
  -n dev | grep "kind:" | sort | uniq -c
# 预期：不出现 postgresql 相关资源
```

- [ ] **Step 5: 最终提交（如有遗漏文件）**

```bash
git status
# 如有未跟踪文件，添加并提交
```
