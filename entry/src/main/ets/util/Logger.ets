import { hilog } from "@kit.PerformanceAnalysisKit"

class Logger {
  private domain = 0
  private tag = "fhl"
  public info(msg: string) {
    hilog.info(this.domain, this.tag, msg)
  }

  public warn(msg: string) {
    hilog.warn(this.domain, this.tag, msg)
  }

  public error(msg: string) {
    hilog.error(this.domain, this.tag, msg)
  }

  public debug(msg: string) {
    hilog.debug(this.domain, this.tag, msg)
  }
}

export default new Logger()