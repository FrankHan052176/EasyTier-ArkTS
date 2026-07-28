import { hilog } from '@kit.PerformanceAnalysisKit'

const STARTUP_DOMAIN = 0x9527
const STARTUP_TAG = 'ET_STARTUP'

let baseTime: number = 0
let lastTime: number = 0

/**
 * 开屏阶段耗时打点。
 *
 * 走 hilog API（release 构建会裁掉 console 调用），设备侧
 * `hilog | grep ET_STARTUP` 即可读到每个阶段的累计耗时与相邻增量。
 */
export function startupMark(name: string): void {
  const now = Date.now()
  if (baseTime === 0) {
    baseTime = now
    lastTime = now
  }
  hilog.info(STARTUP_DOMAIN, STARTUP_TAG, '%{public}s', `+${now - baseTime}ms d=${now - lastTime}ms ${name}`)
  lastTime = now
}
