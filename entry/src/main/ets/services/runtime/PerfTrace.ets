import { hilog } from '@kit.PerformanceAnalysisKit'

const PERF_DOMAIN = 0x9527
const PERF_TAG = 'ET_PERF'

/**
 * 运行期耗时打点（info 级）。
 *
 * 必须走 hilog API 而不是 console.info：release 构建会把 console 调用裁掉，
 * 打点就全丢了。设备侧 `hilog | grep ET_PERF` 取全部记录。
 */
export function perfLog(message: string): void {
  hilog.info(PERF_DOMAIN, PERF_TAG, '%{public}s', message)
}

/** 一次计时：new 的时刻开始，end() 输出耗时 */
export class PerfSpan {
  private readonly name: string
  private readonly startedAt: number

  constructor(name: string) {
    this.name = name
    this.startedAt = Date.now()
  }

  end(detail: string = ''): number {
    const cost = Date.now() - this.startedAt
    hilog.info(PERF_DOMAIN, PERF_TAG, '%{public}s', `${this.name} cost=${cost}ms ${detail}`)
    return cost
  }
}
