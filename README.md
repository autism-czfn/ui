# Autism Q&A UI

用户界面，用于搜索自闭症相关内容。

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
