import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'

import { removeFootage } from '../../dist/electron/services/archive-files.js'

test('removeFootage deletes footage and preserves every other project file', () => {
  const project = fs.mkdtempSync(path.join(os.tmpdir(), 'edithub-archive-'))
  fs.mkdirSync(path.join(project, 'FOOTAGE'))
  fs.mkdirSync(path.join(project, 'READY VIDEOS'))
  fs.writeFileSync(path.join(project, 'FOOTAGE', 'raw.mov'), 'raw')
  fs.writeFileSync(path.join(project, 'READY VIDEOS', 'final.mp4'), 'final')
  fs.writeFileSync(path.join(project, '.edithub.json'), '{}')

  removeFootage(project)

  assert.equal(fs.existsSync(path.join(project, 'FOOTAGE')), false)
  assert.equal(fs.readFileSync(path.join(project, 'READY VIDEOS', 'final.mp4'), 'utf8'), 'final')
  assert.equal(fs.readFileSync(path.join(project, '.edithub.json'), 'utf8'), '{}')
  fs.rmSync(project, { recursive: true, force: true })
})
