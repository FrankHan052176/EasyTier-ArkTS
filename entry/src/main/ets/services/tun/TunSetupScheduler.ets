export interface TunSetupRequest {
  ip: string
  mask: number
  magicDNS: boolean
  needExitNode: boolean
  routes: string[]
  signature: string
  trigger: string
}

export interface TunSetupSchedulerOptions {
  debounceMs: number
  getCurrentSignature: () => string
  getInFlight: () => boolean
  onSchedule: (request: TunSetupRequest) => void
  onClearTimer: (timerId: number) => void
  onLog: (message: string) => void
}

export class TunSetupScheduler {
  private pendingRequest: TunSetupRequest | undefined = undefined
  private timerId: number | undefined = undefined
  private readonly options: TunSetupSchedulerOptions

  constructor(options: TunSetupSchedulerOptions) {
    this.options = options
  }

  clear(): void {
    this.pendingRequest = undefined
    this.clearTimer()
  }

  schedule(request: TunSetupRequest): void {
    if (request.signature === this.options.getCurrentSignature() && !this.options.getInFlight()) {
      this.pendingRequest = undefined
      this.clearTimer()
      this.options.onLog(`Skip equivalent TUN setup trigger=${request.trigger} sig=${request.signature}`)
      return
    }
    this.pendingRequest = request
    if (this.options.getCurrentSignature().length === 0 && !this.options.getInFlight()) {
      this.flush()
      return
    }
    this.clearTimer()
    this.timerId = setTimeout(() => {
      this.timerId = undefined
      this.flush()
    }, this.options.debounceMs)
    this.options.onLog(`Queued TUN setup trigger=${request.trigger} sig=${request.signature}`)
  }

  flush(): void {
    if (this.options.getInFlight() || !this.pendingRequest) {
      return
    }
    const request = this.pendingRequest
    this.pendingRequest = undefined
    if (request.signature === this.options.getCurrentSignature()) {
      this.options.onLog(`Drop equivalent pending TUN setup trigger=${request.trigger} sig=${request.signature}`)
      return
    }
    this.options.onSchedule(request)
  }

  private clearTimer(): void {
    if (this.timerId !== undefined) {
      this.options.onClearTimer(this.timerId)
      this.timerId = undefined
    }
  }
}
