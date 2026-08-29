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
  private scheduled: boolean = false

  enqueue(owner: number, uiContext: UIContext, action: () => void): void {
    this.queue.push(new EditFrameWork(owner, uiContext, action))
    this.scheduleNext()
  }

  cancel(owner: number): void {
    this.queue = this.queue.filter((work: EditFrameWork) => work.owner !== owner)
  }

  private scheduleNext(): void {
    if (this.scheduled || this.queue.length === 0) {
      return
    }
    const work = this.queue.shift()
    if (!work) {
      return
    }
    this.scheduled = true
    const run = () => {
      this.scheduled = false
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
      // UIContext 已失效时丢弃该 owner 的陈旧工作，避免队列永久停住。
      this.scheduled = false
      this.cancel(work.owner)
      this.scheduleNext()
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
