# PRD v1.1（AI 友好版 / Vibe Coding 版）
**项目代号**：AI-First Local Productivity App  
**技术栈**：Flutter（Windows 优先，其次 Android）+ SQLite（FTS5）+ WebDAV（坚果云）  
**核心原则**：本地真源、AI 全权路由、强 AI 搜索、可扩展、中文友好、动画丝滑

---

## 0. 一句话目标
做一个 **AI 驱动的一体化本地效率 App**：用户只用自然语言输入，AI 决定写入 **待办 / 笔记 / 收藏 / 搜索 / 专注计时 / 维护**；数据本地 SQLite 持久化，并通过坚果云 WebDAV 同步 + 每日 14:00 提示全量云备份，确保卸载也不丢。

---

## 1. 范围与非目标

### 1.1 MVP 范围（必须实现）
- 统一输入框（仅自然语言）→ AI Router → 执行动作（创建/搜索/刷新/专注/维护）
- 模块：待办、笔记（原文+整理版）、收藏（标题刷新）、专注计时（稳通知）、搜索（FTS5 + 强 AI）
- 坚果云 WebDAV：增量同步（节流 ≤ 1 次/2 分钟）+ 云备份/云恢复
- 通知：本地通知（必做）；待办外发：飞书机器人 + 邮件（SMTP）
- 多主题预设 + 主题模式（跟随系统/浅色/深色）
- 维护工具：清理垃圾数据、重建索引、清理笔记整理历史（只留最新版）

### 1.2 非目标（明确不做）
- iOS/macOS/Linux/Web（暂不考虑）
- 专注统计/日报/周报（不做，避免负担）
- 全库端到端加密（不做）
- API Key 加密同步（不做；按需求明文同步，但必须提示风险）

---

## 2. 外部约束（强约束，编码时当常量处理）

### 2.1 坚果云 WebDAV 限制（必须适配）
- 访问频率：免费 **30 分钟 ≤ 600 次请求**；付费 **30 分钟 ≤ 1500 次请求**
- 单次请求文件/文件夹总数上限：**750**（需分页/分目录规避）
- 上传大小：默认 **500MB**
- WebDAV 入口与第三方应用授权密码：使用坚果云“第三方应用管理”生成

### 2.2 同步节流（硬）
- 前台同步：**至少间隔 120 秒**才允许再次发起网络同步（包括 PROPFIND/GET/PUT/DELETE）

### 2.3 飞书自定义机器人频控（外发提醒必须限速）
- 自定义机器人：**单租户单机器人 100 次/分钟，5 次/秒**

### 2.4 Android “稳通知”技术路径（强建议）
- 使用 AlarmManager 作为到点触发机制（确保在应用生命周期之外也能按时触发）

### 2.5 Flutter 主题模式（必须支持）
- 支持 `ThemeMode.system`（跟随系统亮/暗）+ 强制浅色 + 强制深色

---

## 3. 交互与导航（减少 Tab；Android 也用侧边栏）

### 3.1 一级导航（固定 3 个入口）
1) **收件箱**（唯一输入框 + 最近流 + AI 失败草稿）  
2) **资料库**（待办 / 笔记 / 收藏 合并；顶部切换与筛选）  
3) **专注**

> 其余都放进侧边栏抽屉（Drawer），避免 Tab 爆炸。

### 3.2 侧边栏（Drawer / Sidebar）
- 搜索（也可在资料库顶部内联搜索框）
- 同步状态 / 手动同步
- 备份与恢复（含备份时间设置）
- AI Provider（base_url / api_key / 模型列表 / 批测）
- 通知渠道（本地 / 飞书 / 邮件）
- 主题（预设 + 主题模式）
- 维护工具

### 3.3 Android 也用侧边栏（不使用底栏）
- Android 手机：Drawer（汉堡按钮 / 左滑）
- Android 平板、Windows：常驻侧边栏（NavigationRail 或自定义 Sidebar）

---

## 4. 动画与性能（“丝滑”必须可验收）

### 4.1 性能验收（MVP）
- 常用交互（页面切换、Drawer 打开、列表滚动、Chip 筛选切换）无明显卡顿/掉帧。
- 资料库列表在 1,000 条记录规模下仍可顺滑滚动（分页/虚拟化/懒加载）。
- AI 返回结果插入列表时使用轻量过渡动画（淡入/高度变化），不阻塞 UI。

### 4.2 工程约束
- 所有 IO（网络/DB/HTML 解析/压缩备份）必须异步，不阻塞 UI 线程。
- 长列表必须使用懒加载/分段加载；不要一次性渲染所有 Markdown 大块内容。
- 任何“批处理”（全选刷新标题/批测模型/恢复/备份）必须展示进度与可取消（至少可中止下一批）。

---

## 5. 核心模块规格

### 5.1 统一输入框：AI 全权路由（不做本地意图判断）
**规则**：用户输入任何文本（含 URL、长文、短句、搜索意图）→ **总是先调用 AI Router** → 得到结构化动作 → App 执行。

**失败回退**：
- AI 超时/错误：输入落到 `inbox_drafts`（草稿队列）
- 草稿支持：重试 AI、手动选择动作（仅作为“AI 不可用时”的兜底，不属于默认路径）

---

### 5.2 待办（Todo）
#### 字段（MVP）
- `title`：必填
- `priority`：三档 `high | medium | low`（默认 medium）
- `tags`：全局标签库，多选；**输入即创建**
- `status`：`open | done`（checkbox 勾选 done）
- `remind_at`：可选（用于本地/外发提醒）

#### 列表默认排序
- `priority` 高→低，然后 `created_at`（建议新→旧）

---

### 5.3 笔记（Note）：原文隐藏入口 + 整理版只读 + 版本
#### 存储双份
- `raw_text`：用户原文（永不丢）
- `organized_md`：AI 整理版（Markdown，只读）

#### UI 展示
- 默认展示整理版（只读）
- 原文不直接显示，仅提供“查看原文”入口（弹窗/抽屉/二级页）

#### 重新整理（生成新版本）
- 点击“重新整理”：生成 `organized_md_v(n+1)`
- 默认保留最近 **5** 个版本
- 维护工具支持：**一键删除所有历史版本，仅保留最新版**

#### AI 深度结合（硬要求）
每次创建/重新整理必须由 AI 生成并写入：
- `title`（标题建议或覆盖策略由 UI 决定）
- `tags`（自动生成，写入全局标签库并绑定）
- `organized_md`（结构化、中文友好、可检索）

---

### 5.4 收藏（Bookmark）：标题刷新（无“批量”，用“多选+全选”）
#### 字段（MVP）
- `url`（唯一）
- `title`（从网页 `<title>` 抓取）
- `last_fetched_at`

#### 标题刷新（两种方式）
1) 单条刷新：列表行按钮/详情按钮  
2) 多选模式：支持 **全选** → “刷新所选”  
> 不再提供单独的“一键刷新所有”，因为全选等价。

---

### 5.5 专注计时（Pomodoro）：稳通知 + 倒计时/正计时 + 中断不算失败
#### 模式
- **倒计时（Countdown）**：专注 X 分钟 → 休息 X/5 分钟
- **正计时（Count-up）**：开始计时向上，用户结束专注 → 休息 = 专注时长/5
- 比例固定：**5:1**（可配置专注基准 x，休息= x/5）

#### 中断规则（关键）
- 专注阶段中断（暂停/结束/意外中断）**不判失败**
- 休息时长按已完成专注计算：完成 15min → 休息 3min（15/5）
- 取整策略（写死，避免歧义）：
  - UI 以分钟显示：`break_minutes = max(1, round(focus_elapsed_minutes / 5))`
  - 内部计时以秒：`break_seconds = max(60, floor(focus_elapsed_seconds / 5))`

#### 不做统计
- 不提供历史统计/图表/排行  
- 但必须做**最小状态持久化**（保证稳通知与崩溃恢复）：当前阶段、起始时间、剩余时间、循环次数等。

#### “通知必须稳”（验收）
- Android：锁屏/后台/Doze 下，到点通知仍能触达；使用 AlarmManager 作为到点触发机制
- Windows：到点可见提醒（toast 或系统通知），且不因 UI 未前台而丢失

---

## 6. 搜索：FTS5 + 强 AI 搜索（必须“有意义”）

### 6.1 本地检索底座（必须）
SQLite FTS5 索引字段：
- Todo：title + tags
- Note：title + raw_text + organized_md + tags
- Bookmark：url + title + tags

### 6.2 强 AI 搜索（默认开启 deep）
**核心模式：Search Agent 生成计划 + App 执行本地检索工具 + AI 重排/解释**
- AI 不直接执行 SQL；只输出“检索计划 JSON”
- App 执行多轮 FTS/过滤，召回 topK
- AI 对候选进行重排并输出命中理由（中文）

> 可选增强：若供应商提供 embeddings（兼容 OpenAI 风格）可加入语义召回；否则用多轮 query 扩展 + 重排实现“足够强”。

---

## 7. AI Provider（OpenAI 兼容，但非 OpenAI 官方）

### 7.1 配置项（用户填写）
- `base_url`（非官方 OpenAI 域名；但接口兼容）
- `api_key`（用户提供）
- `models`：**自动获取**（默认），可选手动覆盖

### 7.2 自动获取模型
- 调用兼容端点：`GET /v1/models`（按 base_url 拼接实现）

### 7.3 测试与批测（必须）
- “测试连接”：`GET /v1/models` + 最小推理请求（chat/completions 或供应商兼容端点）
- “批量测试模型”：对列表内每个 model 做最小推理，记录：
  - success/fail、耗时、错误信息、返回结构兼容性
- 批测并发：2~3（避免把供应商打挂）

---

## 8. 通知系统（本地 + 飞书 + 邮件）

### 8.1 本地通知（必做）
- 用统一 Notification Queue 调度：
  - Todo 提醒（remind_at）
  - 专注阶段切换（focus end / break end）
- Android 到点触发使用 AlarmManager

### 8.2 飞书机器人（Webhook 自定义机器人）
- 用户配置：Webhook URL（可选签名 secret）
- 频控：100 次/分钟，5 次/秒；超限进入退避重试
- 消息格式：MVP 纯文本；后续可扩展卡片消息

### 8.3 邮件（SMTP）
- 用户配置：SMTP host/port、TLS、username/password、From、To
- 必须提供：“发送测试邮件”按钮
- 发送失败：进入队列重试（指数退避），并在 App 内可见失败日志

> 说明：外发通道（飞书/邮件）在移动端若系统限制后台联网，允许“延后补发”；但本地通知必须稳定到点。

---

## 9. 数据层（SQLite 真源）

### 9.1 通用列（所有实体表）
- `id TEXT PRIMARY KEY`（UUID）
- `created_at INTEGER`（epoch ms）
- `updated_at INTEGER`（epoch ms）
- `deleted INTEGER NOT NULL DEFAULT 0`
- `lamport INTEGER NOT NULL`
- `device_id TEXT NOT NULL`

### 9.2 建表 SQL（建议直接照抄）
```sql
-- meta
CREATE TABLE IF NOT EXISTS kv (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS inbox_drafts (
  id TEXT PRIMARY KEY,
  raw_input TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_error TEXT,
  retry_count INTEGER NOT NULL DEFAULT 0
);

-- tags
CREATE TABLE IF NOT EXISTS tags (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS entity_tags (
  entity_type TEXT NOT NULL,          -- 'todo' | 'note' | 'bookmark'
  entity_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  PRIMARY KEY (entity_type, entity_id, tag_id)
);

-- todo
CREATE TABLE IF NOT EXISTS todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  priority INTEGER NOT NULL,          -- 2=high,1=medium,0=low (写死并文档化)
  status INTEGER NOT NULL,            -- 0=open,1=done
  remind_at INTEGER,                  -- epoch ms, nullable
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  lamport INTEGER NOT NULL,
  device_id TEXT NOT NULL
);

-- notes (store latest pointers)
CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  raw_text TEXT NOT NULL,
  latest_version INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  lamport INTEGER NOT NULL,
  device_id TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS note_versions (
  note_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  organized_md TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(note_id, version)
);

-- bookmarks
CREATE TABLE IF NOT EXISTS bookmarks (
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL UNIQUE,
  title TEXT,
  last_fetched_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  lamport INTEGER NOT NULL,
  device_id TEXT NOT NULL
);

-- focus (only minimal runtime state, no history)
CREATE TABLE IF NOT EXISTS focus_state (
  id TEXT PRIMARY KEY,                -- always single row, id='singleton'
  mode TEXT NOT NULL,                 -- 'countdown' | 'countup'
  phase TEXT NOT NULL,                -- 'focus' | 'break' | 'idle'
  started_at INTEGER,                 -- epoch ms
  duration_seconds INTEGER,           -- for countdown phase
  elapsed_seconds INTEGER,            -- for countup phase
  focus_ratio_num INTEGER NOT NULL DEFAULT 5,
  focus_ratio_den INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL
);

-- FTS5 (example: one virtual table)
CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
  entity_type,
  entity_id,
  title,
  body,
  tags,
  tokenize = 'unicode61'
);
```

### 9.3 FTS 更新策略
- 写入/更新 todo/note/bookmark/tag 绑定后：更新对应 `search_fts` 行（建议 upsert）
- 同步/恢复后：可全量重建 FTS（维护工具提供“一键重建”）

---

## 10. WebDAV 同步协议（增量 + LWW + 节流 + 预算）

### 10.1 远端目录结构（分散目录，规避 750 限制）
- `meta/clients/<device_id>.json`
- `objects/todo/<id>.json`
- `objects/note/<id>.json`
- `objects/bookmark/<id>.json`
- `objects/tag/<id>.json`
- `objects/secret/api_provider.json`（**明文**，按需求）
- `changes/<device_id>/YYYY-MM-DD/<change_id>.json`

### 10.2 对象 JSON（统一 envelope）
```json
{
  "entity_type": "todo|note|bookmark|tag|secret",
  "id": "uuid",
  "deleted": 0,
  "lamport": 12345,
  "device_id": "device-uuid",
  "updated_at": 1730000000000,
  "payload": { }
}
```

### 10.3 change JSON（最小日志）
```json
{
  "change_id": "ulid-or-uuid",
  "entity_type": "todo|note|bookmark|tag|secret",
  "entity_id": "uuid",
  "op": "upsert|delete",
  "lamport": 12345,
  "device_id": "device-uuid",
  "ts": 1730000000000
}
```

### 10.4 合并规则（LWW）
- 比较 `(lamport, device_id)`：
  - lamport 大者胜
  - 相同则 device_id 字典序决胜（确保确定性）

### 10.5 同步调度
- 前台：≥ 120 秒才能 sync 一次
- 每次 sync 的“请求预算”：限制 PROPFIND/GET/PUT/DELETE 次数，避免撞坚果云频率上限
- 遇到 429/5xx：指数退避；写入 sync 状态与错误日志

---

## 11. 云备份/云恢复（全量、不加密、前台弹窗）

### 11.1 备份提示
- 默认：每日 **14:00（本地时区）** 弹窗提示备份；用户可在设置修改时间
- **只在前台执行**：用户点击“开始备份”才进行，显示进度条
- 若 14:00 不在前台：下次打开补提示“今日备份未完成，是否现在备份？”

### 11.2 备份内容与格式
- 备份文件：`backup-YYYYMMDD-HHMM.zip`
- zip 内：
  - `db.sqlite`（一致性快照）
  - `manifest.json`（schema_version、created_at、app_version、device_id）
- 云端路径：`backups/YYYY-MM-DD/backup-...zip`
- 保留策略：默认保留最近 30 份（可配置）

### 11.3 恢复
- 从云端选择备份 → 下载 → 校验 manifest → 覆盖本地 db
- 覆盖前自动生成本地临时备份（回滚用）

---

## 12. 维护工具（“对中文用户友好”的可解释维护）
必须提供按钮级动作（每项有确认弹窗与结果提示）：
- 清理软删除数据（超过 X 天）
- 清理孤儿标签（无引用）
- 重建 FTS
- SQLite optimize / VACUUM
- **清理笔记整理历史：仅保留最新版**
- 云端 changes 清理（基于 meta checkpoint）

---

## 13. 主题系统（多预设 + 三种模式）
- 主题模式：跟随系统/浅色/深色
- 主题预设：Material / iOS 风格 / Claude 风格 / …（可扩展）
- 实现方式：设计 tokens（颜色/字体/圆角/间距/阴影）+ 组件映射（新主题只加 tokens，不改业务）

---

## 14. 中文用户友好（硬要求）
- 默认语言：简体中文
- 时间表达理解：支持中文自然语言时间（明天下午三点、下周一、月底前等）→ 交给 AI Router/Parser 产出标准时间戳
- 文案与错误提示中文化：同步/AI/provider/备份失败必须可读
- 输入框对中文 IME 友好：不吞字、不抖动、不因候选框导致 UI 跳动
- 搜索：默认 deep（多轮扩展 + 重排），让“记不住关键词”也能找到

---

## 15. 安全与风险提示（API Key 明文同步）
- 首次开启“同步 AI 凭据”：弹出风险确认（必须勾选“我已知晓风险”）
- 提供“一键清除云端 AI 凭据”按钮
- 提示：API Key 泄露可能导致费用损失/滥用风险（文档化 + UI 提示）

---

# 附录 A：AI Router 输出契约（JSON Schema v1.1）
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "app.ai.router.schema.v1.1",
  "type": "object",
  "required": ["action", "confidence", "payload"],
  "properties": {
    "action": {
      "type": "string",
      "enum": [
        "create_todo",
        "create_note",
        "create_bookmark",
        "search",
        "refresh_bookmark_title",
        "start_focus_timer",
        "maintenance"
      ]
    },
    "confidence": { "type": "number", "minimum": 0, "maximum": 1 },
    "payload": { "type": "object" }
  },
  "allOf": [
    {
      "if": { "properties": { "action": { "const": "create_todo" } } },
      "then": {
        "properties": {
          "payload": {
            "type": "object",
            "required": ["title", "priority", "tags"],
            "properties": {
              "title": { "type": "string", "minLength": 1, "maxLength": 200 },
              "priority": { "type": "string", "enum": ["high", "medium", "low"] },
              "tags": {
                "type": "array",
                "items": { "type": "string", "minLength": 1, "maxLength": 40 },
                "maxItems": 20
              },
              "remind_at": {
                "oneOf": [
                  { "type": "string", "minLength": 5, "maxLength": 40 },
                  { "type": "integer", "minimum": 0 }
                ]
              }
            },
            "additionalProperties": false
          }
        }
      }
    },
    {
      "if": { "properties": { "action": { "const": "create_note" } } },
      "then": {
        "properties": {
          "payload": {
            "type": "object",
            "required": ["title", "tags", "organized_md"],
            "properties": {
              "title": { "type": "string", "minLength": 1, "maxLength": 200 },
              "tags": {
                "type": "array",
                "items": { "type": "string", "minLength": 1, "maxLength": 40 },
                "maxItems": 30
              },
              "organized_md": { "type": "string", "minLength": 1 }
            },
            "additionalProperties": false
          }
        }
      }
    },
    {
      "if": { "properties": { "action": { "const": "create_bookmark" } } },
      "then": {
        "properties": {
          "payload": {
            "type": "object",
            "required": ["url"],
            "properties": {
              "url": { "type": "string", "minLength": 5, "maxLength": 2000 }
            },
            "additionalProperties": false
          }
        }
      }
    },
    {
      "if": { "properties": { "action": { "const": "search" } } },
      "then": {
        "properties": {
          "payload": {
            "type": "object",
            "required": ["query"],
            "properties": {
              "query": { "type": "string", "minLength": 1, "maxLength": 500 },
              "mode": { "type": "string", "enum": ["normal", "deep"], "default": "deep" },
              "filters": {
                "type": "object",
                "properties": {
                  "types": {
                    "type": "array",
                    "items": { "type": "string", "enum": ["todo", "note", "bookmark"] }
                  },
                  "tags": { "type": "array", "items": { "type": "string" } },
                  "todo_status": { "type": "string", "enum": ["open", "done"] },
                  "todo_priority": {
                    "type": "array",
                    "items": { "type": "string", "enum": ["high", "medium", "low"] }
                  }
                },
                "additionalProperties": false
              }
            },
            "additionalProperties": false
          }
        }
      }
    },
    {
      "if": { "properties": { "action": { "const": "refresh_bookmark_title" } } },
      "then": {
        "properties": {
          "payload": {
            "type": "object",
            "properties": {
              "bookmark_id": { "type": "string", "minLength": 8, "maxLength": 80 }
            },
            "required": ["bookmark_id"],
            "additionalProperties": false
          }
        }
      }
    },
    {
      "if": { "properties": { "action": { "const": "start_focus_timer" } } },
      "then": {
        "properties": {
          "payload": {
            "type": "object",
            "properties": {
              "mode": { "type": "string", "enum": ["countdown", "countup"], "default": "countdown" },
              "focus_minutes": { "type": "integer", "minimum": 1, "maximum": 300 },
              "ratio": { "type": "string", "enum": ["5:1"], "default": "5:1" }
            },
            "additionalProperties": false
          }
        }
      }
    },
    {
      "if": { "properties": { "action": { "const": "maintenance" } } },
      "then": {
        "properties": {
          "payload": {
            "type": "object",
            "required": ["task"],
            "properties": {
              "task": {
                "type": "string",
                "enum": [
                  "vacuum",
                  "rebuild_fts",
                  "purge_deleted",
                  "purge_orphan_tags",
                  "purge_note_versions_keep_latest"
                ]
              }
            },
            "additionalProperties": false
          }
        }
      }
    }
  ]
}
```

---

# 附录 B：AI Search Plan 契约（Schema v1.1）
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "app.ai.search_plan.schema.v1.1",
  "type": "object",
  "required": ["original_query", "rounds"],
  "properties": {
    "original_query": { "type": "string", "minLength": 1, "maxLength": 500 },
    "rounds": {
      "type": "array",
      "minItems": 1,
      "maxItems": 3,
      "items": {
        "type": "object",
        "required": ["fts_queries", "filters", "top_k"],
        "properties": {
          "fts_queries": {
            "type": "array",
            "minItems": 1,
            "maxItems": 6,
            "items": { "type": "string", "minLength": 1, "maxLength": 200 }
          },
          "filters": {
            "type": "object",
            "properties": {
              "types": { "type": "array", "items": { "type": "string", "enum": ["todo", "note", "bookmark"] } },
              "tags": { "type": "array", "items": { "type": "string" } },
              "todo_status": { "type": "string", "enum": ["open", "done"] }
            },
            "additionalProperties": false
          },
          "top_k": { "type": "integer", "minimum": 10, "maximum": 200 },
          "reason": { "type": "string", "maxLength": 300 }
        },
        "additionalProperties": false
      }
    }
  },
  "additionalProperties": false
}
```

---

# 附录 C：实现建议（工程切片）

## C1. 推荐目录结构
- `lib/core/`（DB、sync、ai、notifications、backup、theme tokens）
- `lib/features/inbox/`
- `lib/features/library/`（todo/note/bookmark 共用列表 + 顶部切换）
- `lib/features/focus/`
- `lib/features/settings/`
- `lib/ui/`（widgets、animations、theme presets）

## C2. 最小“可跑通”里程碑（建议按顺序）
1) SQLite + FTS5 + 资料库 UI（无 AI）  
2) AI Provider（base_url/api_key + GET models + 批测）  
3) AI Router（schema 校验 + 草稿回退）  
4) Todo/Note/Bookmark 写入与展示 + 标题刷新（含全选）  
5) 强 AI 搜索（Search Plan → FTS 多轮 → 重排）  
6) 专注计时（countdown/countup + 中断休息 + Alarm 稳通知）  
7) WebDAV 增量同步（节流 + 预算 + LWW）+ 云备份/恢复（14:00 提示）  
8) 待办外发：飞书 webhook（限速退避）+ SMTP 邮件  
9) 主题预设 + 主题模式三选项  

---

## 参考链接（供实现时查阅，建议复制到浏览器）
```text
坚果云 WebDAV / 频率限制 / 应用密码：
https://help.jianguoyun.com/?p=2064

飞书自定义机器人：
https://open.feishu.cn/document/client-docs/bot-v3/add-custom-bot?lang=zh-CN

Android AlarmManager（alarms）：
https://developer.android.com/develop/background-work/services/alarms

Flutter themeMode：
https://api.flutter.dev/flutter/material/MaterialApp/themeMode.html

OpenAI Models API（兼容实现可参考其路径与返回结构）：
https://platform.openai.com/docs/api-reference/models
```
