import { randomUUID } from 'crypto'
import db from '../db/index.js'

const EN = ['january','february','march','april','may','june',
            'july','august','september','october','november','december']
const RU = ['январь','февраль','март','апрель','май','июнь',
            'июль','август','сентябрь','октябрь','ноябрь','декабрь']

function monthNumber(raw) {
  const s = String(raw).trim().toLowerCase()
  const n = parseInt(s, 10)
  if (!isNaN(n) && n >= 1 && n <= 12) return n
  const ei = EN.indexOf(s); if (ei >= 0) return ei + 1
  const ri = RU.indexOf(s); if (ri >= 0) return ri + 1
  return null
}

function rowToProject(row) {
  return {
    id:                  row.id,
    workspaceId:         row.workspace_id,
    name:                row.name,
    year:                row.year,
    month:               row.month,
    monthNumber:         row.month_number,
    template:            row.template ?? null,
    footageLinks:        JSON.parse(row.footage_links || '[]'),
    archiveRelativePath: row.archive_relative_path ?? null,
    archiveByteCount:    row.archive_byte_count ?? null,
    archiveChecksum:     row.archive_checksum ?? null,
    archivedAt:          row.archived_at ?? null,
    createdAt:           row.created_at,
    updatedAt:           row.updated_at,
  }
}

// Upsert одного проекта по id. Если id не найден — пробуем найти по
// archiveRelativePath, затем по (year, monthNumber, name). Если ничего — вставляем.
function upsertProject(p, workspaceId, userId) {
  const mn = monthNumber(p.month)
  if (!mn) return { ok: false, reason: `bad month: ${p.month}` }

  const footageJson = JSON.stringify(Array.isArray(p.footageLinks) ? p.footageLinks : [])

  // 1. Найти по id
  let row = p.id ? db.prepare('SELECT * FROM projects WHERE id = ?').get(p.id) : null

  // 2. Fallback — по archiveRelativePath
  if (!row && p.archiveRelativePath) {
    row = db.prepare('SELECT * FROM projects WHERE archive_relative_path = ? AND workspace_id = ?')
      .get(p.archiveRelativePath, workspaceId)
  }

  // 3. Fallback — по (year, monthNumber, name)
  if (!row) {
    row = db.prepare('SELECT * FROM projects WHERE year = ? AND month_number = ? AND name = ? AND workspace_id = ?')
      .get(p.year, mn, p.name, workspaceId)
  }

  if (row) {
    // Обновляем только если входящий updatedAt новее или поле не задано.
    const incomingNewer = !p.updatedAt || !row.updated_at || p.updatedAt > row.updated_at

    if (incomingNewer) {
      db.prepare(`
        UPDATE projects SET
          name                  = ?,
          year                  = ?,
          month                 = ?,
          month_number          = ?,
          template              = COALESCE(?, template),
          footage_links         = ?,
          archive_relative_path = COALESCE(?, archive_relative_path),
          archive_byte_count    = COALESCE(?, archive_byte_count),
          archive_checksum      = COALESCE(?, archive_checksum),
          archived_at           = COALESCE(?, archived_at),
          updated_by_user_id    = ?,
          updated_at            = strftime('%Y-%m-%dT%H:%M:%SZ','now')
        WHERE id = ?
      `).run(
        p.name, p.year, p.month, mn,
        p.template ?? null,
        footageJson,
        p.archiveRelativePath ?? null,
        p.archiveByteCount ?? null,
        p.archiveChecksum ?? null,
        p.archivedAt ?? null,
        userId,
        row.id
      )
    }
    return { ok: true, action: incomingNewer ? 'updated' : 'skipped', id: row.id }
  } else {
    // Вставляем новый — используем переданный id или генерируем.
    const newId = p.id || randomUUID()
    db.prepare(`
      INSERT INTO projects
        (id, workspace_id, name, year, month, month_number, template, footage_links,
         archive_relative_path, archive_byte_count, archive_checksum, archived_at,
         created_by_user_id, updated_by_user_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      newId, workspaceId, p.name, p.year, p.month, mn,
      p.template ?? null, footageJson,
      p.archiveRelativePath ?? null,
      p.archiveByteCount ?? null,
      p.archiveChecksum ?? null,
      p.archivedAt ?? null,
      userId, userId
    )
    return { ok: true, action: 'created', id: newId }
  }
}

export default async function syncRoutes(app) {
  const auth = { onRequest: [app.authenticate] }

  // POST /sync/local-scan
  // Тело: { projects: [...] } — список проектов с локальной машины.
  // Сервер делает upsert каждого и возвращает полный актуальный каталог.
  app.post('/sync/local-scan', {
    ...auth,
    schema: {
      body: {
        type: 'object',
        required: ['projects'],
        properties: {
          projects: {
            type: 'array',
            items: {
              type: 'object',
              required: ['name', 'year', 'month'],
              properties: {
                id:                  { type: 'string' },
                name:                { type: 'string' },
                year:                { type: 'string' },
                month:               { type: 'string' },
                template:            { type: 'string' },
                footageLinks:        { type: 'array', items: { type: 'string' } },
                archiveRelativePath: { type: 'string' },
                archiveByteCount:    { type: 'integer' },
                archiveChecksum:     { type: 'string' },
                archivedAt:          { type: 'string' },
                updatedAt:           { type: 'string' }
              }
            }
          }
        }
      }
    }
  }, async (req, reply) => {
    const { projects } = req.body
    const { workspaceId, userId } = req.user

    const results = { created: 0, updated: 0, skipped: 0, failed: [] }

    const tx = db.transaction(() => {
      for (const p of projects) {
        const r = upsertProject(p, workspaceId, userId)
        if (!r.ok) {
          results.failed.push({ name: p.name, reason: r.reason })
        } else {
          results[r.action] = (results[r.action] || 0) + 1
        }
      }
    })
    tx()

    const allProjects = db.prepare(`
      SELECT * FROM projects WHERE workspace_id = ?
      ORDER BY year DESC, month_number DESC, name ASC
    `).all(workspaceId).map(rowToProject)

    return { sync: results, projects: allProjects }
  })

  // POST /sync/import-icloud-archives
  // Тело: { archives: [...] } — список архивов, найденных импортером.
  // Такая же дедупликация, как local-scan.
  app.post('/sync/import-icloud-archives', {
    ...auth,
    schema: {
      body: {
        type: 'object',
        required: ['archives'],
        properties: {
          archives: {
            type: 'array',
            items: {
              type: 'object',
              required: ['name', 'year', 'month', 'archiveRelativePath'],
              properties: {
                id:                  { type: 'string' },
                name:                { type: 'string' },
                year:                { type: 'string' },
                month:               { type: 'string' },
                archiveRelativePath: { type: 'string' },
                archiveByteCount:    { type: 'integer' },
                archivedAt:          { type: 'string' }
              }
            }
          }
        }
      }
    }
  }, async (req) => {
    const { archives } = req.body
    const { workspaceId, userId } = req.user

    const results = { created: 0, updated: 0, skipped: 0, failed: [] }

    const tx = db.transaction(() => {
      for (const a of archives) {
        const r = upsertProject(
          { ...a, archivedAt: a.archivedAt || new Date().toISOString() },
          workspaceId, userId
        )
        if (!r.ok) results.failed.push({ name: a.name, reason: r.reason })
        else results[r.action] = (results[r.action] || 0) + 1
      }
    })
    tx()

    return { sync: results }
  })
}
