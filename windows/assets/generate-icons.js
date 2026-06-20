/**
 * Run with: node generate-icons.js
 * Generates a simple tray-icon.png and icon.png using raw pixel data.
 * No external dependencies required.
 *
 * For production, replace these with proper designed icons.
 */

const fs = require('fs')
const path = require('path')
const zlib = require('zlib')

// Write a minimal PNG file with a colored circle
function createCirclePng(size, r, g, b) {
  const width = size
  const height = size
  const radius = size / 2 - 1

  // Raw pixel data: RGBA
  const pixels = Buffer.alloc(width * height * 4, 0)

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const cx = x - width / 2
      const cy = y - height / 2
      const dist = Math.sqrt(cx * cx + cy * cy)
      const idx = (y * width + x) * 4

      if (dist <= radius) {
        // Inside circle
        const alpha = dist > radius - 1 ? Math.round(255 * (radius - dist)) : 255
        pixels[idx] = r
        pixels[idx + 1] = g
        pixels[idx + 2] = b
        pixels[idx + 3] = alpha

        // Add an "E" letter (very rough approximation with pixels)
        if (size >= 16) {
          const lx = Math.round(cx + width / 2)
          const ly = Math.round(cy + height / 2)
          const cx2 = Math.round(width * 0.35)
          const cy2 = Math.round(height * 0.25)
          const cw = Math.round(width * 0.3)
          const ch = Math.round(height * 0.5)

          const isE =
            // Left bar
            (lx === cx2 && ly >= cy2 && ly <= cy2 + ch) ||
            // Top bar
            (ly === cy2 && lx >= cx2 && lx <= cx2 + cw) ||
            // Middle bar
            (ly === Math.round(height / 2) && lx >= cx2 && lx <= cx2 + Math.round(cw * 0.75)) ||
            // Bottom bar
            (ly === cy2 + ch && lx >= cx2 && lx <= cx2 + cw)

          if (isE) {
            pixels[idx] = 255
            pixels[idx + 1] = 255
            pixels[idx + 2] = 255
            pixels[idx + 3] = 255
          }
        }
      }
    }
  }

  return encodePng(width, height, pixels)
}

function encodePng(width, height, pixels) {
  // PNG signature
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])

  // IHDR chunk
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8   // bit depth
  ihdr[9] = 2   // color type: RGB (we'll handle alpha separately)
  // Actually use color type 6 (RGBA)
  ihdr[9] = 6
  ihdr[10] = 0  // compression
  ihdr[11] = 0  // filter
  ihdr[12] = 0  // interlace

  // Filter + scanline raw data
  const scanlines = Buffer.alloc((1 + width * 4) * height)
  for (let y = 0; y < height; y++) {
    const offset = y * (1 + width * 4)
    scanlines[offset] = 0 // filter: none
    pixels.copy(scanlines, offset + 1, y * width * 4, (y + 1) * width * 4)
  }

  const compressed = zlib.deflateSync(scanlines)

  const makeChunk = (type, data) => {
    const len = Buffer.alloc(4)
    len.writeUInt32BE(data.length, 0)
    const typeBuffer = Buffer.from(type, 'ascii')
    const crcInput = Buffer.concat([typeBuffer, data])
    const crc = crc32(crcInput)
    const crcBuf = Buffer.alloc(4)
    crcBuf.writeUInt32BE(crc >>> 0, 0)
    return Buffer.concat([len, typeBuffer, data, crcBuf])
  }

  return Buffer.concat([
    signature,
    makeChunk('IHDR', ihdr),
    makeChunk('IDAT', compressed),
    makeChunk('IEND', Buffer.alloc(0)),
  ])
}

// CRC32 implementation
function crc32(buf) {
  const table = makeCrcTable()
  let crc = 0xffffffff
  for (let i = 0; i < buf.length; i++) {
    crc = (crc >>> 8) ^ table[(crc ^ buf[i]) & 0xff]
  }
  return (crc ^ 0xffffffff) >>> 0
}

function makeCrcTable() {
  const table = []
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) {
      if (c & 1) c = 0xedb88320 ^ (c >>> 1)
      else c = c >>> 1
    }
    table[n] = c
  }
  return table
}

// Generate icons
const assetsDir = __dirname
const trayIcon = createCirclePng(16, 109, 109, 240) // #6d6df0
const appIcon = createCirclePng(256, 109, 109, 240)

fs.writeFileSync(path.join(assetsDir, 'tray-icon.png'), trayIcon)
fs.writeFileSync(path.join(assetsDir, 'icon.png'), appIcon)

console.log('Generated tray-icon.png and icon.png')
console.log('For production, replace these with proper designed icons.')
console.log('Note: icon.ico for NSIS needs to be created separately (use an online converter).')
