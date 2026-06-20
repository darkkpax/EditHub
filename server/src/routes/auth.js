import bcrypt from 'bcrypt'
import { randomUUID } from 'crypto'
import db from '../db/index.js'

export default async function authRoutes(app) {
  // POST /auth/register — первичная настройка, создаёт аккаунт + workspace.
  // Работает только если пользователей ещё нет (закрытый инструмент).
  app.post('/auth/register', {
    schema: {
      body: {
        type: 'object',
        required: ['email', 'password', 'workspaceName'],
        properties: {
          email:         { type: 'string', format: 'email' },
          password:      { type: 'string', minLength: 8 },
          workspaceName: { type: 'string', minLength: 1 }
        }
      }
    }
  }, async (req, reply) => {
    const userCount = db.prepare('SELECT COUNT(*) as n FROM users').get().n
    if (userCount >= 2) {
      return reply.code(403).send({ error: 'Registration closed. Max 2 users.' })
    }

    const { email, password, workspaceName } = req.body
    const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email)
    if (existing) return reply.code(409).send({ error: 'Email already registered.' })

    const hash = await bcrypt.hash(password, 12)
    const userId = randomUUID()

    // Первый пользователь создаёт workspace, второй вступает в существующий.
    const tx = db.transaction(() => {
      db.prepare('INSERT INTO users (id, email, password_hash) VALUES (?, ?, ?)').run(userId, email, hash)

      let workspaceId
      const existing = db.prepare('SELECT id FROM workspaces LIMIT 1').get()
      if (existing) {
        workspaceId = existing.id
      } else {
        workspaceId = randomUUID()
        db.prepare('INSERT INTO workspaces (id, name) VALUES (?, ?)').run(workspaceId, workspaceName)
      }

      db.prepare('INSERT OR IGNORE INTO workspace_members (workspace_id, user_id, role) VALUES (?, ?, ?)').run(
        workspaceId, userId, userCount === 0 ? 'owner' : 'member'
      )
      return workspaceId
    })

    const workspaceId = tx()
    const token = app.jwt.sign({ userId, workspaceId }, { expiresIn: '30d' })
    return { token, userId, workspaceId }
  })

  // POST /auth/login
  app.post('/auth/login', {
    schema: {
      body: {
        type: 'object',
        required: ['email', 'password'],
        properties: {
          email:    { type: 'string' },
          password: { type: 'string' }
        }
      }
    }
  }, async (req, reply) => {
    const { email, password } = req.body
    const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email)
    if (!user) return reply.code(401).send({ error: 'Invalid email or password.' })

    const ok = await bcrypt.compare(password, user.password_hash)
    if (!ok) return reply.code(401).send({ error: 'Invalid email or password.' })

    const member = db.prepare('SELECT workspace_id FROM workspace_members WHERE user_id = ?').get(user.id)
    if (!member) return reply.code(403).send({ error: 'User has no workspace.' })

    const token = app.jwt.sign(
      { userId: user.id, workspaceId: member.workspace_id },
      { expiresIn: '30d' }
    )
    return { token, userId: user.id, workspaceId: member.workspace_id }
  })

  // POST /auth/logout — клиент просто удаляет токен; эндпоинт для симметрии.
  app.post('/auth/logout', { onRequest: [app.authenticate] }, async () => {
    return { ok: true }
  })

  // GET /me
  app.get('/me', { onRequest: [app.authenticate] }, async (req) => {
    const user = db.prepare('SELECT id, email, created_at FROM users WHERE id = ?').get(req.user.userId)
    const workspace = db.prepare('SELECT id, name FROM workspaces WHERE id = ?').get(req.user.workspaceId)
    return { user, workspace }
  })
}
