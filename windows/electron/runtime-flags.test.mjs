import test from 'node:test'
import assert from 'node:assert/strict'

import { isDropFXDisabled } from '../dist/electron/runtime-flags.js'

test('DropFX is disabled when EDITHUB_DISABLE_DROPFX is set to 1', () => {
  assert.equal(isDropFXDisabled({ EDITHUB_DISABLE_DROPFX: '1' }), true)
})

test('DropFX stays enabled by default', () => {
  assert.equal(isDropFXDisabled({}), false)
})
