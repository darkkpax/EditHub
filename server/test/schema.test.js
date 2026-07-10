import assert from 'node:assert/strict'
import test from 'node:test'

import Database from 'better-sqlite3'

import { initializeSchema } from '../src/db/schema.js'

test('initializeSchema creates all account and project tables', () => {
  const db = new Database(':memory:')

  initializeSchema(db)

  const tables = db.prepare(`
    SELECT name FROM sqlite_master
    WHERE type = 'table'
    ORDER BY name
  `).all().map((row) => row.name)

  assert.deepEqual(
    tables.filter((name) => !name.startsWith('sqlite_')),
    ['projects', 'users', 'workspace_members', 'workspaces'],
  )
  db.close()
})
