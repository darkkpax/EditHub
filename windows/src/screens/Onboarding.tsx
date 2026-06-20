import React, { useState } from 'react'
import { useStore } from '../store/useStore'

interface Step {
  id: string
  title: string
  hint: string
  field: keyof import('../store/useStore').Settings
  placeholder: string
  autoDetect?: string
}

const STEPS: Step[] = [
  {
    id: 'projectsFolder',
    title: 'Where are your projects?',
    hint: 'Folder where EditHub will create and find your DaVinci project folders.',
    field: 'projectsFolder',
    placeholder: 'D:\\Projects',
  },
  {
    id: 'downloadsFolder',
    title: 'Where are your Downloads?',
    hint: 'EditHub watches this folder for enhanced audio files (e.g. *-enhanced-v2.wav).',
    field: 'downloadsFolder',
    placeholder: 'C:\\Users\\You\\Downloads',
    autoDetect: 'auto',
  },
  {
    id: 'dropfxLibrary',
    title: 'Where is your sound library?',
    hint: 'Root folder with your SFX packs. DropFX will index everything inside.',
    field: 'dropfxLibrary',
    placeholder: 'D:\\Sounds',
  },
  {
    id: 'davinciPath',
    title: 'Where is DaVinci Resolve?',
    hint: 'Path to Resolve.exe. EditHub will launch it when you open a project.',
    field: 'davinciPath',
    placeholder: 'C:\\Program Files\\Blackmagic Design\\DaVinci Resolve\\Resolve.exe',
    autoDetect: 'C:\\Program Files\\Blackmagic Design\\DaVinci Resolve\\Resolve.exe',
  },
]

export default function Onboarding({ onDone }: { onDone: () => void }) {
  const { setSettings, addToast } = useStore()
  const [step, setStep] = useState(0)
  const [values, setValues] = useState<Record<string, string>>({
    projectsFolder: '',
    downloadsFolder: '',
    dropfxLibrary: '',
    davinciPath: 'C:\\Program Files\\Blackmagic Design\\DaVinci Resolve\\Resolve.exe',
    icloudPath: '',
    autoArchiveDays: '30',
    autoImportPatterns: '-enhanced,-enhanced-v2',
  })

  const current = STEPS[step]
  const isLast = step === STEPS.length - 1
  const value = values[current.field] || ''

  const pickFolder = async () => {
    const picked = await window.edithub.pickFolder()
    if (picked) setValues((v) => ({ ...v, [current.field]: picked }))
  }

  const next = () => {
    if (isLast) finish()
    else setStep((s) => s + 1)
  }

  const finish = async () => {
    const settings = {
      projectsFolder: values.projectsFolder || 'D:\\Projects',
      downloadsFolder: values.downloadsFolder || '',
      dropfxLibrary: values.dropfxLibrary || '',
      davinciPath: values.davinciPath || STEPS[3].placeholder,
      icloudPath: values.icloudPath || '',
      autoArchiveDays: 30,
      autoImportPatterns: ['-enhanced', '-enhanced-v2'],
    }
    try {
      await window.edithub.setSettings(settings as any)
      setSettings(settings)
      addToast({ type: 'success', message: 'Setup complete! Welcome to EditHub.' })
      onDone()
    } catch {
      onDone()
    }
  }

  const canSkip = current.id !== 'projectsFolder'

  return (
    <div style={{
      height: '100%',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      padding: 32,
      gap: 0,
      background: 'var(--bg)',
    }}>
      {/* Logo */}
      <div style={{
        width: 56,
        height: 56,
        borderRadius: 16,
        background: 'var(--brand-grad)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 24,
        fontWeight: 800,
        color: '#fff',
        marginBottom: 20,
        animation: 'pop-in 0.4s var(--ease-spring) both',
      }}>
        E
      </div>

      {/* Step dots */}
      <div style={{ display: 'flex', gap: 6, marginBottom: 28 }}>
        {STEPS.map((_, i) => (
          <div key={i} style={{
            width: i === step ? 20 : 6,
            height: 6,
            borderRadius: 3,
            background: i === step ? 'var(--accent)' : 'var(--sep)',
            transition: 'all 0.3s var(--ease-spring)',
          }} />
        ))}
      </div>

      {/* Card */}
      <div
        key={current.id}
        className="card"
        style={{
          width: '100%',
          maxWidth: 480,
          padding: 28,
          display: 'flex',
          flexDirection: 'column',
          gap: 20,
          animation: 'slide-in 0.25s var(--ease-spring) both',
          border: '1px solid var(--sep)',
        }}
      >
        <div>
          <p style={{ fontSize: 11, color: 'var(--accent)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 6 }}>
            Step {step + 1} of {STEPS.length}
          </p>
          <h2 style={{ fontSize: 20, fontWeight: 700, color: 'var(--txt)', marginBottom: 8 }}>
            {current.title}
          </h2>
          <p style={{ fontSize: 13, color: 'var(--dim)', lineHeight: 1.5 }}>
            {current.hint}
          </p>
        </div>

        <div style={{ display: 'flex', gap: 8 }}>
          <input
            value={value}
            onChange={(e) => setValues((v) => ({ ...v, [current.field]: e.target.value }))}
            placeholder={current.placeholder}
            style={{ flex: 1, fontSize: 13 }}
            onKeyDown={(e) => e.key === 'Enter' && value && next()}
          />
          <button
            className="btn btn-secondary"
            onClick={pickFolder}
            style={{ flexShrink: 0, padding: '0 14px' }}
          >
            Browse
          </button>
        </div>

        {current.autoDetect && current.autoDetect !== 'auto' && !value && (
          <p style={{ fontSize: 12, color: 'var(--dim)', marginTop: -12 }}>
            Auto-detected:{' '}
            <button
              style={{ color: 'var(--accent)', background: 'none', border: 'none', cursor: 'pointer', padding: 0, fontSize: 12 }}
              onClick={() => setValues((v) => ({ ...v, [current.field]: current.autoDetect! }))}
            >
              {current.autoDetect}
            </button>
          </p>
        )}

        <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
          {canSkip && (
            <button
              className="btn btn-secondary"
              onClick={next}
              style={{ fontSize: 13 }}
            >
              Skip
            </button>
          )}
          <button
            className="btn btn-primary"
            onClick={next}
            disabled={current.id === 'projectsFolder' && !value}
            style={{ opacity: current.id === 'projectsFolder' && !value ? 0.5 : 1 }}
          >
            {isLast ? 'Finish Setup' : 'Continue'}
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" style={{ marginLeft: 4 }}>
              <path d="M5 3l4 4-4 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
        </div>
      </div>

      <p style={{ marginTop: 16, fontSize: 12, color: 'var(--dim)', textAlign: 'center' }}>
        You can change these paths any time in Settings
      </p>
    </div>
  )
}
