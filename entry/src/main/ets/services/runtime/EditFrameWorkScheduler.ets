import { FrameCallback, UIContext } from '@kit.ArkUI'

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

class EditFrameWorkCallback extends FrameCallback {
  private readonly handler: () => void
  private fired: boolean = false

  constructor(handler: () => void) {
    super()
    this.handler = handler
  }

  onFrame(_frameTimeNanos: number): void {
    this.run()
  }

  private run(): void {
    if (this.fired) {
      return
    }
    this.fired = true
    this.handler()
  }
}

/**
 * 配置编辑页的全局逐帧预算器。
 *
 * 分区挂载、List 行放行和递归 group 子项都经过同一个 FIFO，确保整个页面
 * 每个 VSync 最多新增一批重 UI，而不是每个组件实例各自新增一批。
 */
class EditFrameWorkScheduler {
  private queue: EditFrameWork[] = []
  private inFlight: EditFrameWork | undefined = undefined

  enqueue(owner: number, uiContext: UIContext, action: () => void): void {
    this.queue.push(new EditFrameWork(owner, uiContext, action))
    this.scheduleNext()
  }

  cancel(owner: number): void {
    this.queue = this.queue.filter((work: EditFrameWork) => work.owner !== owner)
    if (this.inFlight?.owner === owner) {
      // postFrameCallback 没有取消接口；解除全局闩锁，旧 callback 到达时按 identity 直接丢弃。
      this.inFlight = undefined
      this.scheduleNext()
    }
  }

  private scheduleNext(): void {
    if (this.inFlight || this.queue.length === 0) {
      return
    }
    const work = this.queue.shift()
    if (!work) {
      return
    }
    this.inFlight = work
    const run = () => {
      if (this.inFlight !== work) {
        return
      }
      this.inFlight = undefined
      try {
        work.action()
      } finally {
        this.scheduleNext()
      }
    }
    // 当前 action 只更新可见编辑树；由它产生的下一帧继续放行一个全页工作项。
    // 离屏 List 不进入该队列，避免无 dirty node 时 frame callback 饿死。
    try {
      work.uiContext.postFrameCallback(new EditFrameWorkCallback(run))
    } catch (_) {
      // 注册失败时同步执行这一个有界 action：调用方可清除 scheduled 标记，队列也不会卡死。
      if (this.inFlight === work) {
        this.inFlight = undefined
      }
      try {
        work.action()
      } finally {
        this.scheduleNext()
      }
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
