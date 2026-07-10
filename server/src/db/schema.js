export function initializeSchema(db) {
  db.pragma('journal_mode = WAL')
  db.pragma('foreign_keys = ON')

  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id            TEXT PRIMARY KEY,
      email         TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
    );

    CREATE TABLE IF NOT EXISTS workspaces (
      id         TEXT PRIMARY KEY,
      name       TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
    );

    CREATE TABLE IF NOT EXISTS workspace_members (
      workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role         TEXT NOT NULL DEFAULT 'member',
      PRIMARY KEY (workspace_id, user_id)
    );

    CREATE TABLE IF NOT EXISTS projects (
      id                    TEXT PRIMARY KEY,
      workspace_id          TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      name                  TEXT NOT NULL,
      year                  TEXT NOT NULL,
      month                 TEXT NOT NULL,
      month_number          INTEGER NOT NULL,
      template              TEXT,
      footage_links         TEXT NOT NULL DEFAULT '[]',
      archive_relative_path TEXT,
      archive_byte_count    INTEGER,
      archive_checksum      TEXT,
      archived_at           TEXT,
      created_by_user_id    TEXT REFERENCES users(id),
      updated_by_user_id    TEXT REFERENCES users(id),
      created_at            TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
      updated_at            TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
    );

    CREATE INDEX IF NOT EXISTS idx_projects_workspace ON projects(workspace_id);
    CREATE INDEX IF NOT EXISTS idx_projects_year_month ON projects(year, month_number);
  `)
}
