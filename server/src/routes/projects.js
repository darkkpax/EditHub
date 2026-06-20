import { randomUUID } from 'crypto'
import db from '../db/index.js'

// Парсер месяца → номер 1-12 (зеркало MonthKey.swift).
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
    id:                   row.id,
    workspaceId:          row.workspace_id,
    name:                 row.name,
    year:                 row.year,
    month:                row.month,
    monthNumber:          row.month_number,
    template:             row.template ?? null,
    footageLinks:         JSON.parse(row.footage_links || '[]'),
    archiveRelativePath:  row.archive_relative_path ?? null,
    archiveByteCount:     row.archive_byte_count ?? null,
    archiveChecksum:      row.archive_checksum ?? null,
    archivedAt:           row.archived_at ?? null,
    createdByUserId:      row.created_by_user_id ?? null,
    updatedByUserId:      row.updated_by_user_id ?? null,
    createdAt:            row.created_at,
    updatedAt:            row.updated_at,
  }
}

export default async function projectRoutes(app) {
  const auth = { onRequest: [app.authenticate] }

  // GET /projects — все проекты workspace, новые первыми.
  app.get('/projects', auth, async (req) => {
    const rows = db.prepare(`
      SELECT * FROM projects
      WHERE workspace_id = ?
      ORDER BY year DESC, month_number DESC, name ASC
    `).all(req.user.workspaceId)
    return rows.map(rowToProject)
  })

  // POST /projects — создать проект.
  app.post('/projects', {
    ...auth,
    schema: {
      body: {
        type: 'object',
        required: ['id', 'name', 'year', 'month'],
        properties: {
          id:                  { type: 'string' },
          name:                { type: 'string', minLength: 1 },
          year:                { type: 'string', pattern: '^\\d{4}$' },
          month:               { type: 'string' },
          template:            { type: 'string' },
          footageLinks:        { type: 'array', items: { type: 'string' } },
          archiveRelativePath: { type: 'string' },
          archiveByteCount:    { type: 'integer' },
          archiveChecksum:     { type: 'string' },
          archivedAt:          { type: 'string' }
        }
      }
    }
  }, async (req, reply) => {
    const { id, name, year, month, template, footageLinks, archiveRelativePath,
            archiveByteCount, archiveChecksum, archivedAt } = req.body

    const mn = monthNumber(month)
    if (!mn) return reply.code(400).send({ error: `Unrecognised month: ${month}` })

    const existing = db.prepare('SELECT id FROM projects WHERE id = ?').get(id)
    if (existing) return reply.code(409).send({ error: 'Project with this id already exists. Use PATCH to update.' })

    db.prepare(`
      INSERT INTO projects
        (id, workspace_id, name, year, month, month_number, template, footage_links,
         archive_relative_path, archive_byte_count, archive_checksum, archived_at,
         created_by_user_id, updated_by_user_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id, req.user.workspaceId, name, year, month, mn,
      template ?? null,
      JSON.stringify(footageLinks ?? []),
      archiveRelativePath ?? null,
      archiveByteCount ?? null,
      archiveChecksum ?? null,
      archivedAt ?? null,
      req.user.userId, req.user.userId
    )

    const row = db.prepare('SELECT * FROM projects WHERE id = ?').get(id)
    return reply.code(201).send(rowToProject(row))
  })

  // PATCH /projects/:id — частичное обновление (last-write-wins по updatedAt).
  app.patch('/projects/:id', {
    ...auth,
    schema: {
      params: { type: 'object', properties: { id: { type: 'string' } } },
      body: {
        type: 'object',
        properties: {
          name:                { type: 'string', minLength: 1 },
          year:                { type: 'string', pattern: '^\\d{4}$' },
          month:               { type: 'string' },
          template:            { type: 'string' },
          footageLinks:        { type: 'array', items: { type: 'string' } },
          archiveRelativePath: { type: 'string', nullable: true },
          archiveByteCount:    { type: 'integer',  nullable: true },
          archiveChecksum:     { type: 'string',   nullable: true },
          archivedAt:          { type: 'string',   nullable: true }
        }
      }
    }
  }, async (req, reply) => {
    const row = db.prepare('SELECT * FROM projects WHERE id = ? AND workspace_id = ?')
      .get(req.params.id, req.user.workspaceId)
    if (!row) return reply.code(404).send({ error: 'Project not found.' })

    const b = req.body
    const mn = b.month != null ? monthNumber(b.month) : null
    if (b.month != null && !mn) return reply.code(400).send({ error: `Unrecognised month: ${b.month}` })

    db.prepare(`
      UPDATE projects SET
        name                 = COALESCE(?, name),
        year                 = COALESCE(?, year),
        month                = COALESCE(?, month),
        month_number         = COALESCE(?, month_number),
        template             = COALESCE(?, template),
        footage_links        = COALESCE(?, footage_links),
        archive_relative_path = COALESCE(?, archive_relative_path),
        archive_byte_count   = COALESCE(?, archive_byte_count),
        archive_checksum     = COALESCE(?, archive_checksum),
        archived_at          = COALESCE(?, archived_at),
        updated_by_user_id   = ?,
        updated_at           = strftime('%Y-%m-%dT%H:%M:%SZ','now')
      WHERE id = ?
    `).run(
      b.name ?? null,
      b.year ?? null,
      b.month ?? null,
      mn,
      b.template ?? null,
      b.footageLinks != null ? JSON.stringify(b.footageLinks) : null,
      b.archiveRelativePath !== undefined ? b.archiveRelativePath : null,
      b.archiveByteCount    !== undefined ? b.archiveByteCount    : null,
      b.archiveChecksum     !== undefined ? b.archiveChecksum     : null,
      b.archivedAt          !== undefined ? b.archivedAt          : null,
      req.user.userId,
      req.params.id
    )

    return rowToProject(db.prepare('SELECT * FROM projects WHERE id = ?').get(req.params.id))
  })

  // DELETE /projects/:id
  app.delete('/projects/:id', auth, async (req, reply) => {
    const row = db.prepare('SELECT id FROM projects WHERE id = ? AND workspace_id = ?')
      .get(req.params.id, req.user.workspaceId)
    if (!row) return reply.code(404).send({ error: 'Project not found.' })
    db.prepare('DELETE FROM projects WHERE id = ?').run(req.params.id)
    return reply.code(204).send()
  })
}
