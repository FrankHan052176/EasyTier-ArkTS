export const HOME_LAYOUT_SCHEMA_VERSION: number = 1

const REMOTE_CONTROL_INTRODUCTION_VERSION: number = 1
const REMOTE_CONTROL_CARD_TYPE: string = 'RemoteControl'
const LEGACY_SHARED_PEERS_CARD_TYPE: string = 'SharedPeers'

export interface HomeLayoutMigrationResult {
  sequence: string
  version: number
  changed: boolean
}

function layoutEntryType(entry: string): string {
  const separator = entry.indexOf('_')
  return separator < 0 ? entry : entry.substring(0, separator)
}

function nextFreeRow(entries: string[]): number {
  let nextRow = 0
  entries.forEach((entry: string) => {
    const fields = entry.split('_')
    if (fields.length < 5) {
      return
    }
    const y = Number.parseInt(fields[2])
    const height = Number.parseInt(fields[4])
    if (!Number.isNaN(y) && !Number.isNaN(height) && y >= 0 && height > 0) {
      nextRow = Math.max(nextRow, y + height)
    }
  })
  return nextRow
}

function introduceRemoteControlCard(sequence: string): string {
  const entries = sequence.length > 0 ? sequence.split('|').filter((entry: string) => entry.length > 0) : []
  let remoteControlIndex = -1
  let legacySharedPeersIndex = -1

  for (let index = 0; index < entries.length; index++) {
    const type = layoutEntryType(entries[index])
    if (type === REMOTE_CONTROL_CARD_TYPE && remoteControlIndex < 0) {
      remoteControlIndex = index
    } else if (type === LEGACY_SHARED_PEERS_CARD_TYPE && legacySharedPeersIndex < 0) {
      legacySharedPeersIndex = index
    }
  }

  if (remoteControlIndex >= 0) {
    return entries.filter((entry: string, index: number) => {
      return index === remoteControlIndex || layoutEntryType(entry) !== REMOTE_CONTROL_CARD_TYPE
    }).filter((entry: string) => layoutEntryType(entry) !== LEGACY_SHARED_PEERS_CARD_TYPE).join('|')
  }

  if (legacySharedPeersIndex >= 0) {
    const legacyEntry = entries[legacySharedPeersIndex]
    entries[legacySharedPeersIndex] = REMOTE_CONTROL_CARD_TYPE +
      legacyEntry.substring(LEGACY_SHARED_PEERS_CARD_TYPE.length)
    return entries.join('|')
  }

  entries.push(`${REMOTE_CONTROL_CARD_TYPE}_0_${nextFreeRow(entries)}_2_1`)
  return entries.join('|')
}

export function migrateHomeLayoutSequence(sequence: string, storedVersion: number): HomeLayoutMigrationResult {
  let migratedSequence = sequence
  if (storedVersion < REMOTE_CONTROL_INTRODUCTION_VERSION) {
    migratedSequence = introduceRemoteControlCard(migratedSequence)
  }
  const migratedVersion = Math.max(storedVersion, HOME_LAYOUT_SCHEMA_VERSION)
  return {
    sequence: migratedSequence,
    version: migratedVersion,
    changed: migratedSequence !== sequence || storedVersion < HOME_LAYOUT_SCHEMA_VERSION
  }
}
