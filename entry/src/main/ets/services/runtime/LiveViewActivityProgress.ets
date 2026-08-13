const ACTIVITY_PROGRESS_STEP = 0.5
const ACTIVITY_PROGRESS_LOW_THRESHOLD = 50
const ACTIVITY_PROGRESS_HIGH_THRESHOLD = 80
const ACTIVITY_PROGRESS_LOW_INCREASE_PROBABILITY = 0.7
const ACTIVITY_PROGRESS_MID_INCREASE_PROBABILITY = 0.5
const ACTIVITY_PROGRESS_HIGH_INCREASE_PROBABILITY = 0.2

export const LIVE_VIEW_ACTIVITY_PROGRESS_MAX = 99.5
export const LIVE_VIEW_ACTIVITY_PROGRESS_EDGE_STEPS = 10

export class LiveViewActivityProgress {
  private progressValue: number = 0
  private forcedIncreaseRemaining: number = LIVE_VIEW_ACTIVITY_PROGRESS_EDGE_STEPS
  private forcedDecreaseRemaining: number = 0

  reset(): void {
    this.progressValue = 0
    this.forcedIncreaseRemaining = LIVE_VIEW_ACTIVITY_PROGRESS_EDGE_STEPS
    this.forcedDecreaseRemaining = 0
  }

  advance(randomValue: number = Math.random()): number {
    if (this.shouldIncrease(randomValue)) {
      this.progressValue = Math.min(LIVE_VIEW_ACTIVITY_PROGRESS_MAX,
        this.progressValue + ACTIVITY_PROGRESS_STEP)
      if (this.progressValue >= LIVE_VIEW_ACTIVITY_PROGRESS_MAX) {
        this.forcedIncreaseRemaining = 0
        this.forcedDecreaseRemaining = LIVE_VIEW_ACTIVITY_PROGRESS_EDGE_STEPS
      }
    } else {
      this.progressValue = Math.max(0, this.progressValue - ACTIVITY_PROGRESS_STEP)
      if (this.progressValue <= 0) {
        this.forcedIncreaseRemaining = LIVE_VIEW_ACTIVITY_PROGRESS_EDGE_STEPS
        this.forcedDecreaseRemaining = 0
      }
    }
    return this.progressValue
  }

  private shouldIncrease(randomValue: number): boolean {
    if (this.forcedIncreaseRemaining > 0) {
      this.forcedIncreaseRemaining -= 1
      return true
    }
    if (this.forcedDecreaseRemaining > 0) {
      this.forcedDecreaseRemaining -= 1
      return false
    }

    const normalizedRandomValue = Math.min(Math.max(randomValue, 0), 0.999999)
    if (this.progressValue < ACTIVITY_PROGRESS_LOW_THRESHOLD) {
      return normalizedRandomValue < ACTIVITY_PROGRESS_LOW_INCREASE_PROBABILITY
    }
    if (this.progressValue > ACTIVITY_PROGRESS_HIGH_THRESHOLD) {
      return normalizedRandomValue >= 1 - ACTIVITY_PROGRESS_HIGH_INCREASE_PROBABILITY
    }
    return normalizedRandomValue < ACTIVITY_PROGRESS_MID_INCREASE_PROBABILITY
  }
}
