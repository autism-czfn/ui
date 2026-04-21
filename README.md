# Autism Q&A UI

用户界面，用于搜索自闭症相关内容。

---

## 最新更新 / Latest Changes (2026-04-20)

本次更新新增了 **💬 Chat** 标签页（第 6 个标签），提供基于 SSE 流式传输的对话式问答，并将个人日志、临床数据库、实时网络三路检索结果并排展示。同时更新了 Nginx 配置，新增 `/api/chat/` 长连接反代路由。

### Chat Tab — 对话式问答（新增标签页）

**UI 面板（`#panel-chat`）**

- 导航栏新增 💬 **Chat** 标签按钮（第 6 个标签）。
- 整体采用「viewport-locked」布局：输入框始终固定在底部可见区域，消息列表独立滚动，不受页面高度影响。
- 支持移动端自适应：小屏幕下证据面板堆叠在对话下方。

**消息区域**

- 用户消息（右对齐，`chat-bubble-user` 靛蓝气泡）和助手消息（左对齐，`chat-bubble-asst` 白色气泡）分别渲染。
- 助手消息支持 **Markdown 渲染**（`chat-md` 样式：标题、列表、加粗、斜体、段落）。
- 流式输出期间显示光标动画（`chat-cursor`，闪烁动效）。
- 消息发送失败时显示错误提示 + **Retry** 按钮，点击后移除失败气泡并重新发送。

**输入区域**

- 自动高度调整的 `<textarea>`（`overflow-y:hidden` + 动态 `scrollHeight`）。
- 发送中状态：按钮禁用 + 文案切换为「Sending…」，图标隐藏；完成后自动恢复焦点。
- 「✕ New conversation」按钮：清空对话历史、重置状态栏、重置检索点、重置证据面板占位文本。
- 支持 `Enter` 键发送（`Shift+Enter` 换行）。

**状态栏（`#chat-status-bar`）**

- 骨架动画（`#chat-status-skeleton`）在每次新请求时先显示，后端返回 `metadata` 事件后替换为真实数据。
- 显示三组信息：
  - **Topic**（`intent`）：`BEHAVIOR_PATTERN` / `INTERVENTION` / `MEDICAL` / `SAFETY` 等，映射为友好标签。
  - **Approach**（`mode`）：`HYBRID_LOG_FIRST` / `HYBRID_EVIDENCE_FIRST` / `EXPLAIN_PATTERN` / `SAFETY_EXPANDED_MODE` 等完整描述文字。
  - **Top 3 triggers**：以 `chat-chip` 圆角标签形式展示。

**搜索注释（user bubble 下方）**

- 收到 `metadata` 事件后，在用户气泡下方自动插入检索注释行（`chat-search-annotation`）：
  - 主查询（`rewritten_query`）以靛蓝色 chip 显示。
  - 子查询（`sub_queries[]`）以灰色 chip 追加。
  - 实时网络搜索的查询词（`live` 检索触发后）以深靛蓝 chip 追加（`🌐 <query>`）。

**右侧证据面板（`#chat-evidence`，268px 固定宽度）**

三路检索结果分三个可折叠卡片展示，各含状态指示点（灰色闲置 → 琥珀色搜索中 → 绿色完成）：

| 卡片 | 数据来源 | SSE 事件 |
|---|---|---|
| 📋 Personal Logs | 用户个人日志历史 | `evidence_logs` |
| 📘 Clinical Evidence | 爬取数据库 | `evidence_crawl` |
| 🌐 Live Sources | 实时网络搜索 | `evidence_live` |

- 日志卡片支持点击展开/折叠完整文本（日期、触发类型 chip、严重程度色标 S1–S5）。
- 临床与实时来源渲染标题 + 可点击域名链接（`_refRow`）。
- 实时来源卡片显示「(N sites searched)」徽章。

**SSE 流式协议**

| 事件类型 | 处理函数 |
|---|---|
| `metadata` | 更新状态栏、注入搜索注释 |
| `retrieval` | 更新三路检索点颜色 |
| `evidence_logs` | 渲染 Personal Logs 面板 |
| `evidence_crawl` | 渲染 Clinical Evidence 面板 |
| `evidence_live` | 渲染 Live Sources 面板 |
| `token` | 流式追加助手文字到气泡 |
| `done` | 完成渲染（Markdown 解析、状态重置） |
| `error` | 显示错误气泡 + Retry 按钮 |

### Nginx — `/api/chat/` 路由（`config/nginx/ui.conf`）

- 新增 `location /api/chat/` 块，**优先于** `/api/` 匹配，代理至 `collect_backend`（端口 18001）。
- 关键 SSE 配置：`proxy_buffering off`、`proxy_cache off`、`chunked_transfer_encoding on`、`proxy_read_timeout 3600s`。
- 限流：`perip_collect` zone，burst=3，nodelay。

### 移除

- Log Today 标签页中的「🎙 Audio Quick Log」快速录音入口卡片已移除（确认表单 `#audio-confirm-section` 保留，供程序化调用）。

### 变更文件

| 文件 | 变更 |
|---|---|
| `index.html` | +851 行：新增 Chat 标签页完整 UI、CSS、JS；移除 Audio Quick Log 入口卡片 |
| `config/nginx/ui.conf` | +22 行：新增 `/api/chat/` SSE 反代路由 |

### 依赖的后端变更

| 后端 API | 说明 | 状态 |
|---|---|---|
| `POST /api/chat/stream` (SSE) | Chat 对话流式响应（`metadata` / `retrieval` / `evidence_*` / `token` / `done` / `error` 事件） | 需部署 |

---

## 此前更新 / Previous Changes (2026-04-19)

本次更新新增了 Settings 标签页、Service Worker 离线缓存、音频快速日志确认流程、改进的错误处理、历史日志翻页等 5 项功能（P-UI-1 ～ P-UI-4, P-UI-7），并包含多项 Bug 修复。

### P-UI-1 — Settings Tab（设置标签页）

- 导航栏新增 ⚙️ **Settings** 标签页（第 5 个标签）。
- **Child Information** 卡片：可设置孩子显示名（`child_display_name`）。
- **Preferences** 卡片：可选择时区（完整 IANA 列表）和界面语言（9 种）。
- 设置通过 `POST /collect/user-settings` 持久化到服务器；同时写入 `localStorage` 作为离线缓存。
- 离线时显示 "Offline mode" 横幅，提交失败时将待同步数据存入 `localStorage.settings_pending`。
- 页面启动时自动调用 `loadSettings()`，将已保存的受众模式（`audience_mode`）从独立 localStorage 键迁移至 `ui_preferences`。

### P-UI-2 — Service Worker / Offline Support（Service Worker 离线支持）

- 新增 `sw.js`，实现分层缓存策略：
  - **CDN 资源**（Tailwind、marked.js、DOMPurify）：Cache First，安装时预缓存。
  - **`index.html`**：Network First，网络失败时回退缓存。
  - **`/api/search`、`/api/insights*`、`/api/weekly-summary`**：Network First，最多缓存最近 5 条搜索响应；离线时响应头携带 `X-Served-From: cache`。
  - **SSE 流（`/api/search/stream`）、写操作（`/collect/*`）、证据/来源/统计 API**：Network Only，永不缓存。
- 页面加载后通过 `navigator.serviceWorker.register('/sw.js')` 静默注册（失败不影响功能）。

### P-UI-3 — Audio Quick Log with Confirmation（音频快速日志确认流程）

- Log Today 标签新增 "🎙 Audio Quick Log" 卡片。
- 录音完成后，展示 **Review & Confirm** 确认表单：
  - 原始转录文本（只读展示）
  - 触发类型下拉（必填）
  - 严重程度滑条（1–5）
  - 情境与结果提示输入框
  - 提取置信度展示（trigger / severity / overall 百分比）
  - 警告区域（自动填充低置信提示）
- 点击 "✅ Confirm & Save" 调用 `POST /collect/logs` 保存事件；Cancel 隐藏表单。

### P-UI-4 — Improved Error Handling（改进错误处理）

- 新增 `createTimeoutSignal(ms)` 工具函数，为所有 `fetch` 调用附加 30 秒超时 `AbortController`。
- 新增 `classifyFetchError(err, status)` 函数，区分四种错误场景：
  - 离线 / `Failed to fetch` → "You're offline. Check your connection and try again."
  - `AbortError` → "Request timed out. Please try again."
  - HTTP 5xx → "Server error (N). Try again in a moment."
  - HTTP 4xx → "Request failed (N). Please reload and try again."
- `fallbackFetch`、`confirmAudioLog`、`loadLogsHistory` 等关键路径均已接入。

### P-UI-7 — Past Logs History（历史日志翻页）

- Log Today 底部新增 "📋 Past Logs" 卡片，展示当天以前的所有日志。
- 每页 20 条，使用 `GET /collect/logs?limit=20&offset=N&days=3650` 拉取，自动过滤当天条目。
- `buildLogCard` 渲染：日期、严重程度色标（绿/黄/红）、触发类型 chip、事件摘要、情境文本。
- "Load more" 按钮追加加载；全部加载完毕显示 "All logs loaded."

### Bug Fixes & Improvements

- **字段名修正**：Evidence 卡片与 Traceability 面板的 `organization_name` 字段改为 `source_name`，与后端保持一致。
- **共现率精度修正**：`buildInsightCard` 中 `co_occurrence_pct` 现在乘以 100 并保留 1 位小数（`(val*100).toFixed(1)%`）。
- **证据来源细分标签**：Insight 卡片 Layer 3 显示 "X database · Y live · searched Z websites" 明细。
- **安全横幅升级**：`safety-banner` 改为顶部固定横幅（`position:fixed`）+ 内联紧急帮助说明（911 / 988 / 急诊）。
- **周报标题**："This Week at a Glance" 改为 "Past 7 Days at a Glance"。
- **Insights 时间戳**：`generated_at` 由 "X ago" 改为格式化时间戳（如 "Apr 19, 10:30 AM"）。
- **Insights 错误处理**：网络错误时通过 `showBanner` 显示具体错误信息，而非静默失败。
- **Top Triggers 日期范围**：标题新增 "(from – to)" 日期范围显示。
- **来源计数标签**：`renderSourceCards` 升级为 async，从 `/api/sources` 拉取并展示 "N crawled + M live sources · showing top K"。
- **Insights API child_id 参数**：`fetchInsightsWithFallback` 和 trigger chips 的 insights 请求均附加 `child_id` 参数。
- **启动优化**：`DOMContentLoaded` 时预调用 `getSourceCounts()`、`populateTimezones()`、`loadSettings()`。
- **打印支持**：`@media print` 规则新增 `[id^="evidence-panel-"] { display:block !important; }`，打印时自动展开所有证据面板。
- **Insights 刷新按钮**：旁边新增 "🖨 Print report" 按钮（`window.print()`）。

### 变更文件

| 文件 | 变更 |
|---|---|
| `index.html` | 新增 Settings 标签页、Audio Quick Log 确认流程、Past Logs 翻页、Service Worker 注册、错误处理工具函数；多项 bug 修复 |
| `sw.js` | 新文件，分层 Service Worker 缓存（P-UI-2） |

### 依赖的后端变更

| 后端 API | 对应 UI 功能 | 状态 |
|---|---|---|
| `POST /collect/user-settings` | P-UI-1 Settings 保存 | 需部署 |
| `GET /collect/user-settings` | P-UI-1 Settings 加载 | 需部署 |
| `GET /collect/logs?offset=&days=3650` | P-UI-7 历史日志翻页 | 需部署 |
| `GET /collect/logs?offset=` param | P-UI-7 Load more | 需部署 |

---

## 此前更新 / Previous Changes (2026-04-17)

本次更新实现了 plan.txt UI Section 中 Phase 1–3 的绝大部分优先项（P1–P5、P7），将搜索面板从简单结果列表升级为具备来源可信度、证据追溯、受众切换和行为洞察的综合信息工作台。

### P1.1 — Source Attribution Badges（来源可信度徽章）

- 卡片标签优先显示 `source_name`（如 "National Institutes of Health"），无则回退平台名。
- Authority Tier 徽章：🟢 Official (Tier 1) / 🔵 Academic (Tier 2) / ⚪ Verified Nonprofit (Tier 3)。
- Audience Type 徽章：🟣 Parent Guide / 🟠 Clinical Reference。
- 所有新字段均可选，后端未部署前显示与此前一致。

### P1.2 — Evidence Traceability Panel（证据追溯面板）

- 每张搜索结果卡片存储 `data-chunk-id`，底部新增 "Show source details" 按钮。
- 点击后 lazy-fetch `GET /api/evidence/{chunk_id}`，展开内联详情：页面标题、引文块引、信任徽章、"View full source" 外链。
- 点击引用上标 `[N]` 时自动滚动到对应卡片并展开追溯面板。
- 若 API 返回失败，优雅降级显示 "Source details unavailable" + 原始链接。

### P2 — Confidence & Evidence Strength（置信度与证据强度）

- 搜索摘要卡片新增置信度进度条（`confProgressHtml`）：Strong 90% 绿 / Moderate 50% 黄 / Limited 15% 灰。
- 新增 "Based on N sources" 标注，数量取自 `results` SSE 事件的 `results.length`。

### P3 — Source List Modal（来源列表弹窗）

- 顶部导航栏新增 "ℹ️ Sources" 按钮，点击打开全屏遮罩弹窗。
- 弹窗从 `GET /api/sources` 拉取数据，按 Tier 1/2/3 分组展示来源名、国家、语言。
- 顶部静态说明解释三级信任体系。
- 加载失败时显示错误提示 + 重试按钮。

### P4 — Audience Toggle（受众模式切换）

- 搜索过滤器新增 "Audience" 下拉：Parent Mode / Clinical Mode。
- 选择自动存入 `localStorage`，刷新后保持。
- 切换时若当前已有搜索结果，自动以新 `?audience=` 参数重新搜索。
- 同时传递给 SSE 流式搜索和非流式 fallback。

### P5 — Trigger-Based Search Suggestions（触发因素快捷搜索）

- 搜索面板新增 trigger chips 区域，优先展示近 7 天用户自身日志的 top triggers。
- 若无个人数据，回退到 `GET /triggers/vocabulary`（collect API）或内置默认词列表。
- 点击 chip 自动填入 "What helps with {trigger} in children with autism?" 并立即搜索。

### P7 — Insights Tab Redesign（洞察标签页重构）

- **API 升级**：`loadInsights()` 优先请求 `GET /api/insights/full`（含 evidence + recommendations），404/500 时自动回退到基础 `/api/insights`。
- **4 层洞察卡片**（`buildInsightCard`）：
  - Layer 1 — 摘要行：`trigger → outcome` + 置信度徽章 + co-occurrence 百分比。
  - Layer 2 — 个人数据：靛蓝色框，显示 "Observed in X out of Y episodes (Z%)" + 样本数。
  - Layer 3 — 外部证据（默认折叠）：`toggleEvidence()` 展开/收起，每条证据渲染为 `buildEvidenceCard`（📘 组织名 + 置信标签 + 摘要 + 外链）。
  - Layer 4 — 推荐行动：✓ 列表，无数据时整层隐藏。
- **Top Triggers 增强**：显示 `raw_signals`（红色）和 `is_safety` 安全徽章。
- **空态处理**：无 pattern 时提示 "Not enough data yet — keep logging daily…"。
- **打印支持**：`@media print` 自动展开所有 evidence-panel。

### Bug Fixes & Improvements

- **时区修复**：新增 `localDateStr()` 工具函数，`loadTodayEntry()` 和 `submitCombined()` 改用本地日期（非 UTC），修复跨午夜时日志匹配不到的问题。日志查询范围从 `days=1` 扩大到 `days=2` 以覆盖边界情况。
- **Insights 缓存**：新增 `_insightsCacheValid` 标志，提交日志后自动失效；切换标签页时 `AbortController` 取消进行中的请求，防止竞态。
- **Patterns 字段兼容**：`renderPatternInsights` 同时接受 `data.patterns` 和 `data.pattern_cards`。

### 变更文件

| 文件 | 变更 |
|---|---|
| `index.html` | +224 行新增功能代码：P1.2 追溯面板、P2 置信度条、P3 来源弹窗、P4 受众切换、P5 trigger chips、P7 洞察卡片重构；搜索流增加 audience 参数；时区修复；insights 缓存 |

### 依赖的后端变更

| 后端 API | 对应 UI 功能 | 状态 |
|---|---|---|
| Search P1.4: `source_name`, `authority_tier`, `audience_type` 字段 | P1.1 徽章 | 未部署（UI 已向后兼容） |
| Search P3: `GET /api/evidence/{chunk_id}` | P1.2 追溯面板 | 未部署（UI 优雅降级） |
| Search P1.4: `GET /api/sources` | P3 来源弹窗 | 未部署（UI 显示重试） |
| Search API: `?audience=` 参数 | P4 受众切换 | 未部署（参数已传递） |
| Collect API: `GET /triggers/vocabulary` | P5 trigger chips | 未部署（UI 回退默认词） |
| Search P8: `GET /api/insights/full` | P7 洞察卡片 L3+L4 | 未部署（UI 回退基础端点） |

---

### 此前更新 / Previous Changes (2026-04-16)

Source Attribution Badges (P1.1) 首次实现 — 搜索结果卡片新增来源可信度标识。

### 此前更新 / Previous Changes (2026-04-15)

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

- **UI 端口**：`18000`（`serve.py`、`README.md`、`config/nginx/ui.conf` 同步配置）。
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
  <LAN_IP>:18000

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
│  🧩 Autism Support   ● N indexed ℹ️Src │  ← 导航栏 + Sources 弹窗入口
│  [Search][Log Today][Insights][Clin][💬]│  ← 标签页（第 6 个：Chat）
├─────────────────────────────────────────┤
│  搜索框 + [Search] 按钮                  │  ← 问题输入
│  ▸ Filters（来源/时间/数量/受众）        │  ← 折叠过滤器（含 Audience 切换）
│  [Noise] [Sleep] [Transitions] …        │  ← Trigger chips 快捷搜索
├─────────────────────────────────────────┤
│  Answer            Strong evidence ██▓░ │  ← LLM 摘要 + 置信度条
│  早期自闭症迹象包括… [1][3]              │  ← Based on N sources
├─────────────────────────────────────────┤
│  Sources                                │  ← 搜索结果卡片
│  [1] Reddit  "Signs my son was…"        │
│  [2] PubMed 🟢Official 🟣Parent Guide  │  ← 信任+受众徽章
│      "Early markers of ASD…"            │
│      Smith et al. · 2023 · 🔓 open     │
│      [Show source details]              │  ← 追溯面板（lazy-fetch）
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
| 受众（Audience） | Parent Mode（家长模式）/ Clinical Mode（临床模式），选择存入 localStorage |

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

### 信任等级 & 受众徽章

搜索结果卡片可显示额外的可信度与受众标识（需后端 Search P1.4 支持）：

| 徽章类型 | 值 | 颜色 |
|---|---|---|
| Authority Tier 1 | Official Source | 绿色 |
| Authority Tier 2 | Academic Source | 蓝色 |
| Authority Tier 3 | Verified Nonprofit | 灰色 |
| Audience: parent_facing | Parent Guide | 紫色 |
| Audience: clinician_facing | Clinical Reference | 琥珀色 |

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

服务启动后访问：**https://\<LAN_IP\>:18000/**（LAN IP 由服务器自动检测）

---

## 依赖关系

UI 服务本身仅依赖 Python 3 标准库（`http.server`、`socketserver`），无需安装任何第三方包。

所有前端依赖（Tailwind、marked.js、DOMPurify）均通过 CDN 加载。
