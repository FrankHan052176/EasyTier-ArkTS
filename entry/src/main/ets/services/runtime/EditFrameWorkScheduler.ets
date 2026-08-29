import { AnimatorOptions, AnimatorResult, UIContext } from '@kit.ArkUI'

class EditFrameWork {
  readonly owner: number
  readonly uiContext: UIContext
  readonly action: () => void

  constructor(owner: number, uiContext: UIContext, action: () => void) {
    this.owner = owner
    this.uiContext = uiContext
    this.action = action
  }
}

const EDIT_FRAME_DRIVER_OPTIONS: AnimatorOptions = {
  duration: 1000,
  easing: 'linear',
  delay: 0,
  fill: 'none',
  direction: 'normal',
  iterations: -1,
  begin: 0,
  end: 1
}
const EDIT_FRAME_DRIVER_IDLE_FRAMES = 6

/**
 * 配置编辑页的全局逐帧预算器。
 *
 * 分区挂载、List 行放行和递归 group 子项都经过同一个 FIFO，确保整个页面
 * 每个 VSync 最多新增一批重 UI，而不是每个组件实例各自新增一批。
 * Animator 只用作 DisplaySync 驱动，不参与任何组件属性插值；队列连续空闲 6 帧后释放。
 */
class EditFrameWorkScheduler {
  private queue: EditFrameWork[] = []
  private driver: AnimatorResult | undefined = undefined
  private driverOwner: number | undefined = undefined
  private idleFrames: number = 0
  private startingDriver: boolean = false
  private fallbackScheduled: boolean = false
  private fallbackRunning: boolean = false

  enqueue(owner: number, uiContext: UIContext, action: () => void): void {
    this.queue.push(new EditFrameWork(owner, uiContext, action))
    this.idleFrames = 0
    this.startDriver()
  }

  cancel(owner: number): void {
    this.queue = this.queue.filter((work: EditFrameWork) => work.owner !== owner)
    if (this.driverOwner === owner) {
      this.stopDriver()
      this.startDriver()
    } else if (this.queue.length === 0) {
      this.stopDriver()
    }
  }

  private startDriver(): void {
    if (this.driver || this.queue.length === 0 || this.startingDriver || this.fallbackScheduled ||
      this.fallbackRunning) {
      return
    }
    const firstWork = this.queue[0]
    if (!firstWork) {
      return
    }

    this.startingDriver = true
    let driver: AnimatorResult | undefined = undefined
    try {
      const createdDriver = firstWork.uiContext.createAnimator(EDIT_FRAME_DRIVER_OPTIONS)
      driver = createdDriver
      createdDriver.onFrame = (_progress: number) => this.runFrame(createdDriver)
      createdDriver.onFinish = () => this.finishDriver(createdDriver)
      createdDriver.onCancel = () => this.finishDriver(createdDriver)
      this.driver = createdDriver
      this.driverOwner = firstWork.owner
      this.idleFrames = 0
      createdDriver.play()
      this.startingDriver = false
    } catch (_) {
      this.startingDriver = false
      if (driver && this.driver === driver) {
        this.stopDriver()
      }
      this.scheduleFallback()
    }
  }

  /**
   * Animator 初始化失败时，每个 timer turn 最多执行一个有界 action。
   * 不能同步 fallback：action 会 enqueue 下一批，持续失败时会递归排空整棵编辑树。
   */
  private scheduleFallback(): void {
    if (this.fallbackScheduled || this.fallbackRunning || this.driver || this.queue.length === 0) {
      return
    }
    this.fallbackScheduled = true
    setTimeout(() => {
      this.fallbackScheduled = false
      if (this.driver || this.queue.length === 0) {
        this.startDriver()
        return
      }
      const work = this.queue.shift()
      if (!work) {
        return
      }
      this.fallbackRunning = true
      try {
        work.action()
      } finally {
        this.fallbackRunning = false
        this.startDriver()
      }
    }, 0)
  }

  private runFrame(driver: AnimatorResult): void {
    if (this.driver !== driver) {
      return
    }
    const work = this.queue.shift()
    if (!work) {
      this.idleFrames++
      if (this.idleFrames >= EDIT_FRAME_DRIVER_IDLE_FRAMES) {
        this.stopDriver()
      }
      return
    }

    this.idleFrames = 0
    try {
      work.action()
    } finally {
      // 状态写入到子组件继续 enqueue 之间可能隔一个 rerender；保留短暂空帧窗口，
      // 避免为每层递归工作重复创建 Animator 并触发数百毫秒的重新起振延迟。
      if (!this.driver) {
        this.startDriver()
      }
    }
  }

  private finishDriver(driver: AnimatorResult): void {
    if (this.driver !== driver) {
      return
    }
    this.driver = undefined
    this.driverOwner = undefined
    this.idleFrames = 0
    this.startDriver()
  }

  private stopDriver(): void {
    const driver = this.driver
    this.driver = undefined
    this.driverOwner = undefined
    this.idleFrames = 0
    if (!driver) {
      return
    }
    // finish/cancel 会额外触发一次 onFrame，先断开回调避免重复消费队列。
    driver.onFrame = (_progress: number) => {}
    driver.onFinish = () => {}
    driver.onCancel = () => {}
    try {
      driver.finish()
    } catch (_) {
    }
  }
}

let nextEditFrameWorkOwner: number = 1

export function allocateEditFrameWorkOwner(): number {
  const owner = nextEditFrameWorkOwner
  nextEditFrameWorkOwner++
  return owner
}

export const editFrameWorkScheduler = new EditFrameWorkScheduler()
