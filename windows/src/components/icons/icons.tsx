import React from 'react'

interface IconProps {
  size?: number
  color?: string
  className?: string
  style?: React.CSSProperties
}

export function IconFolder({ size = 18, color = 'currentColor', className }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className={className}>
      <path d="M2 5a2 2 0 0 1 2-2h3l2 2h5a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5z" />
    </svg>
  )
}

export function IconPlay({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <polygon points="6,4 15,9 6,14" fill={color} stroke="none" />
    </svg>
  )
}

export function IconPause({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="1.8" strokeLinecap="round">
      <line x1="6" y1="4" x2="6" y2="14" />
      <line x1="12" y1="4" x2="12" y2="14" />
    </svg>
  )
}

export function IconDownload({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M9 3v8M5 8l4 4 4-4" />
      <path d="M3 14h12" />
    </svg>
  )
}

export function IconTrash({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 5h12M8 8v5M10 8v5M6 5l1-2h4l1 2" />
      <rect x="4" y="5" width="10" height="10" rx="2" />
    </svg>
  )
}

export function IconArchive({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="3" width="14" height="4" rx="1.5" />
      <path d="M3 7v7a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7" />
      <path d="M7 11h4" />
    </svg>
  )
}

export function IconCloud({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M13.5 12.5H12A4 4 0 0 1 8 8.5a3.5 3.5 0 0 1 6.94-.7H15a2.5 2.5 0 0 1 0 5z" />
      <path d="M4 12.5A3 3 0 0 1 3.5 6.6 4.5 4.5 0 0 1 12 8" />
    </svg>
  )
}

export function IconCheck({ size = 18, color = 'var(--good)' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 9l4 4 6-7" />
    </svg>
  )
}

export function IconPlus({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="1.8" strokeLinecap="round">
      <line x1="9" y1="3" x2="9" y2="15" />
      <line x1="3" y1="9" x2="15" y2="9" />
    </svg>
  )
}

export function IconSearch({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="1.5" strokeLinecap="round">
      <circle cx="8" cy="8" r="5" />
      <path d="M12 12l3.5 3.5" />
    </svg>
  )
}

export function IconDaVinci({ size = 18, color = 'currentColor' }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="9" cy="9" r="7" />
      <path d="M6 6h4a2 2 0 0 1 0 4H8v2" />
      <circle cx="9" cy="13.5" r="0.75" fill={color} stroke="none" />
    </svg>
  )
}

export function IconWaveform({ size = 18, color = 'currentColor', style }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" stroke={color}
      strokeWidth="1.5" strokeLinecap="round" style={style}>
      <line x1="2" y1="9" x2="2" y2="9" />
      <line x1="5" y1="6" x2="5" y2="12" />
      <line x1="8" y1="4" x2="8" y2="14" />
      <line x1="11" y1="7" x2="11" y2="11" />
      <line x1="14" y1="5" x2="14" y2="13" />
      <line x1="16" y1="8" x2="16" y2="10" />
    </svg>
  )
}
