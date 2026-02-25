# WebDAV 同步与备份设计

## 1. 目标

- 本地优先：离线创建、编辑、删除收藏
- 多设备同步：通过 WebDAV 共享变更
- 云备份：可完整恢复（即使同步记录损坏）

## 2. 数据模型（MVP）

`bookmarks` 表（本地 SQLite）：

- `id`：UUID
- `url`：原始 URL
- `normalizedUrl`：标准化 URL（去尾斜杠、排序 query 可选）
- `title`：标题（可空）
- `note`：备注（可空）
- `tags`：标签（JSON 字符串或关联表）
- `createdAt`：创建时间（ISO 8601 UTC）
- `updatedAt`：更新时间（ISO 8601 UTC）
- `deletedAt`：删除时间（可空，软删除）
- `titleUpdatedAt`：标题更新时间（可空）

本地 `sync_state` 表：

- `deviceId`
- `lastPulledOpTs`
- `lastPushedOpTs`

## 3. WebDAV 文件协议

### 3.1 操作日志（增量同步）

文件路径：

`/BookmarksApp/users/{userId}/devices/{deviceId}/ops/{timestamp}_{deviceId}.json`

内容示例：

```json
{
  "deviceId": "win-a1",
  "createdAt": "2026-02-16T09:00:00Z",
  "ops": [
    {
      "opId": "uuid-1",
      "type": "upsert",
      "bookmark": {
        "id": "b1",
        "url": "https://example.com",
        "normalizedUrl": "https://example.com",
        "title": "Example Domain",
        "updatedAt": "2026-02-16T08:59:55Z",
        "deletedAt": null
      }
    }
  ]
}
```

### 3.2 备份快照（恢复用）

文件路径：

`/BookmarksApp/users/{userId}/snapshots/bookmarks_{date}.json`

内容为全量导出（含软删除记录），推荐 gzip 压缩。

## 4. 同步流程（客户端）

1. 本地写入并记录操作日志（outbox）
2. Push：将未上传操作批量写到 WebDAV `ops/`
3. Pull：拉取所有设备 `ops/` 中新文件并合并
4. 冲突处理：
   - 比较 `updatedAt`
   - `deletedAt` 非空且时间更新时优先删除
5. 更新 `sync_state` 游标

## 5. 锁与并发

MVP 可先无全局锁（依赖操作日志幂等合并）。
若后续需要强一致，可在 `lock/sync.lock` 做短租约锁（带过期时间）。

## 6. 标题抓取策略

- 新增 URL 后异步抓取标题并更新本地
- 定时任务刷新超过阈值（如 7 天）未更新标题
- 抓取失败指数退避重试
- 客户端可直接抓；如遇反爬/Cookie/JS 渲染，再启用可选服务端抓取器

## 7. 安全建议

- WebDAV 仅走 HTTPS
- 凭据使用系统安全存储（Android Keystore / Windows Credential Manager）
- 可选：备份快照客户端加密（AES-GCM）

