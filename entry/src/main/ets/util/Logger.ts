import { hilog } from "@kit.PerformanceAnalysisKit"

export const LOG_LOCATE_METADATA = Symbol('log_locate');
export function LogLocate(className: string): ClassDecorator {
  return function (target: any) {
    Reflect.set(target, LOG_LOCATE_METADATA, className)
    if (target.prototype) {
      Reflect.set(target.prototype, LOG_LOCATE_METADATA, className)
    }
  };
}

export class Logger {
  private static domain = 0
  private static tag = "fhl"

  private static getPrefix(target: any): string {
    if (target == null) {
      return "[Null] ";
    }
    const prefix = Reflect.get(target, LOG_LOCATE_METADATA)
    if (prefix) {
      return `[${prefix}] `
    }else if (target.prototype && Reflect.get(target.prototype, LOG_LOCATE_METADATA)) {
      return `[${Reflect.get(target.prototype, LOG_LOCATE_METADATA)}] `
    }else {
      return `[${target.constructor.name}] `
    }
  }

  public static info(msg: string, target: any | string = null) {
    if (typeof target === "string") {
      hilog.info(this.domain, this.tag, "["+target+"] "+msg)
    }else {
      hilog.info(this.domain, this.tag, this.getPrefix(target)+msg)
    }
  }

  public static warn(msg: string, target: any | string = null) {
    if (typeof target === "string") {
      hilog.warn(this.domain, this.tag, "["+target+"] "+msg)
    }else {
      hilog.warn(this.domain, this.tag, this.getPrefix(target)+msg)
    }
  }

  public static error(msg: string, target: any | string = null) {
    if (typeof target === "string") {
      hilog.error(this.domain, this.tag, "["+target+"] "+msg)
    }else {
      hilog.error(this.domain, this.tag, this.getPrefix(target)+msg)
    }
  }

  public static debug(msg: string, target: any | string = null) {
    if (typeof target === "string") {
      hilog.debug(this.domain, this.tag, "["+target+"] "+msg)
    }else {
      hilog.debug(this.domain, this.tag, this.getPrefix(target)+msg)
    }
  }
}