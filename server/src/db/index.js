import Database from 'better-sqlite3'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import { mkdirSync } from 'fs'
import { initializeSchema } from './schema.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const dataDir = join(__dirname, '../../data')
mkdirSync(dataDir, { recursive: true })

const DB_PATH = process.env.DB_PATH || join(dataDir, 'edithub.db')

const db = new Database(DB_PATH)
initializeSchema(db)

export default db
