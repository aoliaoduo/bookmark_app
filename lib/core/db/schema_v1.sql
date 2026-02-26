-- PRD v1.1 schema
-- Todo priority encoding: 2=high, 1=medium, 0=low
-- Todo status encoding: 0=open, 1=done

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

CREATE TABLE IF NOT EXISTS tags (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS entity_tags (
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  PRIMARY KEY (entity_type, entity_id, tag_id)
);

CREATE TABLE IF NOT EXISTS todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  priority INTEGER NOT NULL,
  status INTEGER NOT NULL,
  remind_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  lamport INTEGER NOT NULL,
  device_id TEXT NOT NULL
);

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

CREATE TABLE IF NOT EXISTS focus_state (
  id TEXT PRIMARY KEY,
  mode TEXT NOT NULL,
  phase TEXT NOT NULL,
  started_at INTEGER,
  duration_seconds INTEGER,
  elapsed_seconds INTEGER,
  focus_ratio_num INTEGER NOT NULL DEFAULT 5,
  focus_ratio_den INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS change_log (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL,
  lamport INTEGER NOT NULL,
  device_id TEXT NOT NULL,
  payload_json TEXT,
  created_at INTEGER NOT NULL,
  synced_at INTEGER,
  retry_count INTEGER NOT NULL DEFAULT 0,
  last_error TEXT
);

CREATE TABLE IF NOT EXISTS processed_changes (
  change_id TEXT PRIMARY KEY,
  source_device_id TEXT NOT NULL,
  applied_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sync_state (
  id TEXT PRIMARY KEY,
  last_sync_started_at INTEGER,
  last_sync_finished_at INTEGER,
  next_allowed_sync_at INTEGER,
  backoff_until INTEGER,
  last_error TEXT,
  last_applied_change_id TEXT,
  last_pushed_change_id TEXT,
  request_window_started_at INTEGER,
  request_count_in_window INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
);

CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
  entity_type,
  entity_id,
  title,
  body,
  tags,
  tokenize = 'unicode61'
);
