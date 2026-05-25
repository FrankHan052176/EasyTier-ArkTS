let cloudResetting: boolean = false

export function setCloudResetting(active: boolean): void {
  cloudResetting = active
}

export function isCloudResetting(): boolean {
  return cloudResetting
}
