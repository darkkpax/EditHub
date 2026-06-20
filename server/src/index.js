import Fastify from 'fastify'
import fjwt from '@fastify/jwt'
import authRoutes from './routes/auth.js'
import projectRoutes from './routes/projects.js'
import syncRoutes from './routes/sync.js'

const app = Fastify({ logger: { level: process.env.LOG_LEVEL || 'info' } })

// JWT
const JWT_SECRET = process.env.JWT_SECRET
if (!JWT_SECRET) {
  console.error('ERROR: JWT_SECRET env var is required')
  process.exit(1)
}
await app.register(fjwt, { secret: JWT_SECRET })

// authenticate — хелпер для onRequest
app.decorate('authenticate', async (req, reply) => {
  try {
    await req.jwtVerify()
  } catch {
    reply.code(401).send({ error: 'Unauthorized.' })
  }
})

// Маршруты
await app.register(authRoutes)
await app.register(projectRoutes)
await app.register(syncRoutes)

// Health check
app.get('/health', async () => ({ ok: true, ts: new Date().toISOString() }))

// Запуск
const PORT = parseInt(process.env.PORT || '3000', 10)
const HOST = process.env.HOST || '127.0.0.1'

try {
  await app.listen({ port: PORT, host: HOST })
  console.log(`EditHub server listening on ${HOST}:${PORT}`)
} catch (err) {
  app.log.error(err)
  process.exit(1)
}
