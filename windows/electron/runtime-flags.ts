export function isDropFXDisabled(env: NodeJS.ProcessEnv = process.env): boolean {
  const value = env.EDITHUB_DISABLE_DROPFX?.trim().toLowerCase()
  return value === '1' || value === 'true' || value === 'yes'
}
