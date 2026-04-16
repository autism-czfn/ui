# Autism Q&A UI

用户界面，用于搜索自闭症相关内容。

---

## 最新更新 / Latest Changes (2026-04-15)

今日共 4 次提交，核心是将 UI 从「搜索 + 日志」升级为一站式「Autism Support」多标签工作台。

### 新功能亮点

- **标签页重构**：页面标题由 *Autism Q&A + Daily Log* 改为 **Autism Support**，新增四个标签页：
  - 🔍 **Search** — 原有自闭症检索问答
  - 📋 **Log Today** — 每日事件日志 + 每日检查打分
  - 📊 **Insights** — 周报摘要、触发因素、干预效果
  - 🏥 **Clinician** — 面向临床医生的报告视图
- **今日条目自动回填**（`loadTodayEntry`）：切换到 Log Today 标签时，自动拉取当天已有日志和检查打分填入表单，按钮切换为「Update Log ✅」，避免重复录入。
- **语音自动填写日志**：语音录入后字段自动保存并回填，横幅提示「Saved automatically. Fields filled below for your review.」。
- **每日检查打分**：新增 10 项评分（睡眠、情绪、感官敏感度、食欲、社交耐受、崩溃次数、作息规律、沟通难易、运动量、照护者评分）+ 备注。
- **干预追踪**：Log Today 中可查看未结案干预（`/interventions?status=open`），并提交 outcome（`PUT /interventions/:id/outcome`）。
- **周报渲染适配新 schema**：`renderWeeklySummary` 改为读取 `data.stats.*`（`event_count`、`meltdown_count`、`top_triggers`、`interventions_adopted`）及 `week_start/week_end`。
- **Admin 页面 bug 修复**（commit `bedcc3b`）。
- **Public IP 占位符**（commit `61d5fce`）：为后续外网访问预留配置位。

### 基础设施变更

- **UI 端口迁移**：`18000` → `19000`（`serve.py`、`README.md`、`config/nginx/ui.conf` 同步更新）。
- **Nginx 配置新增**：`config/nginx/ui.conf` 新增 175 行反代配置，upstream 包含 `ui_backend` / `search_backend` / `collect_backend` / `django_admin`，并带基础 WAF 拦截（wp-admin、phpmyadmin、.git、.env 等）与每 IP 限流。
- **API 路径简化**：前端调用移除 `/api/v1` 前缀，改为 `/logs`、`/interventions`、`/daily-checks/:date` 等更短路径。
- **`setup.sh` 扩展**：+107 行 / −…，集成新服务管理流程。

### 变更文件统计

| 文件 | +/− |
|---|---|
| `index.html` | +1541 / −1203（近乎重写，2744 行） |
| `config/nginx/ui.conf` | +175 / −0（全新文件） |
| `setup.sh` | +107 / −… |
| `README.md` | +2 / −2 |
| `serve.py` | +2 / −2 |

### 今日提交

| Commit | 说明 |
|---|---|
| `61d5fce` | add place holder for public ip |
| `bedcc3b` | fix bugs for admin page |
| `16587e7` | fix bugs — 大规模 UI 重构，端口迁移，新增 nginx 配置 |
| `a0fc36b` | fix bugs — 今日条目自动回填、API 路径修正、周报 schema 适配 |

---

## 架构设计

```
用户浏览器
    │
    │  GET /          → index.html（静态页面）
    ▼
UI Web 服务器（serve.py）
  <LAN_IP>:19000

    │
    │  GET /api/search?q=...   跨域请求（CORS）
    │  GET /api/stats
    │  GET /api/health
    ▼
autism-search API 服务器
  <LAN_IP>:3001
    │
    ├── 关键词搜索（PostgreSQL 全文索引）
    ├── 语义搜索（向量嵌入）
    ├── 混合排序（hybrid rerank）
    └── LLM 摘要（claude -p）
```

UI 层本身不含任何搜索逻辑，所有搜索与 AI 摘要均由 `autism-search` 服务完成。

---

## 文件说明

| 文件 | 说明 |
|---|---|
| `index.html` | 完整前端页面，单文件，无构建步骤 |
| `serve.py` | Python 内置 HTTP 静态文件服务器 |
| `setup.sh` | 服务管理菜单（启动 / 停止 / 状态） |

---

## 前端设计

### 技术选型

| 技术 | 说明 |
|---|---|
| Tailwind CSS（CDN） | 样式，无需构建 |
| marked.js（CDN） | 将 LLM 返回的 Markdown 渲染为 HTML |
| DOMPurify（CDN） | 对 LLM 输出进行 XSS 清洗 |
| 原生 `fetch()` | 调用搜索 API，无需任何框架 |

无 npm，无 webpack，无任何构建工具。整个前端就是一个 HTML 文件。

### 页面结构

```
┌─────────────────────────────────────────┐
│  🧩 Autism Q&A        ● N items indexed │  ← 顶部导航栏
├─────────────────────────────────────────┤
│  搜索框 + [Search] 按钮                  │  ← 问题输入
│  ▸ Filters（来源 / 时间 / 数量）         │  ← 折叠过滤器
├─────────────────────────────────────────┤
│  Answer                                 │  ← LLM 摘要（含引用标注）
│  早期自闭症迹象包括… [1][3]              │
├─────────────────────────────────────────┤
│  Sources                                │  ← 搜索结果卡片
│  [1] Reddit  "Signs my son was…"        │
│  [2] PubMed  "Early markers of ASD…"   │
│      Smith et al. · 2023 · 🔓 open     │
│  …                                      │
├─────────────────────────────────────────┤
│  hybrid · search 0.24s · answer 1.2s   │  ← 底部统计
└─────────────────────────────────────────┘
```

### 主要交互流程

1. 用户在搜索框输入问题，点击 **Search** 或按 `Cmd/Ctrl+Enter`
2. 前端通过 `fetch()` 调用 `GET /api/search?q=...&limit=...&source=...&days=...`
3. 收到响应后：
   - `summary` 字段（LLM 摘要）经 `marked.js` 渲染为 HTML，再经 `DOMPurify` 清洗
   - `[1][2][3]` 引用标注转换为可点击的上标，点击后平滑滚动到对应来源卡片
   - `results[]` 渲染为来源卡片，每张卡片展示标题、作者、期刊、日期、摘要、相关度分数条

### 过滤器

| 过滤项 | 说明 |
|---|---|
| 来源（Source） | 按数据来源筛选，如 Reddit、PubMed、Europe PMC 等 16 种 |
| 时间（Time） | 最近 30 天 / 90 天 / 1 年 / 不限 |
| 数量（Results） | 返回前 10 / 20 / 50 条结果 |

过滤器默认折叠，点击展开，使用 HTML 原生 `<details>` 元素，无需 JavaScript。

### 来源卡片配色

不同来源使用不同颜色标签，便于快速区分：

| 来源 | 颜色 |
|---|---|
| Reddit | 橙色 |
| PubMed / Europe PMC | 蓝色 |
| Semantic Scholar / CrossRef | 紫色 |
| bioRxiv | 粉色 |
| RSS / Spectrum News | 绿色 |
| ClinicalTrials.gov | 红色 |
| Wikipedia | 灰蓝色 |

### 错误处理

| 场景 | 处理方式 |
|---|---|
| 搜索服务不可用 | 红色错误横幅 |
| LLM 摘要不可用 | 琥珀色提示，仍显示来源卡片（优雅降级） |
| 无搜索结果 | 提示用户换词或取消过滤器 |
| 请求超过 3 秒 | 提示文字变为"仍在搜索中…" |
| 搜索框为空 | 禁用 Search 按钮，阻止提交 |

---

## 启动方式

```bash
./setup.sh
```

选择 `1) Start / Restart service` 即可。

服务启动后访问：**https://\<LAN_IP\>:19000/**（LAN IP 由服务器自动检测）

---

## 依赖关系

UI 服务本身仅依赖 Python 3 标准库（`http.server`、`socketserver`），无需安装任何第三方包。

所有前端依赖（Tailwind、marked.js、DOMPurify）均通过 CDN 加载。
