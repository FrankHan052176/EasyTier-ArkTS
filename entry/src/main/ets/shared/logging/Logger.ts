import easytier from 'easytier-ohrs'

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
  public static info(msg: string, target: any | string = null) {
    this.write(4, target, msg)
  }

  public static warn(msg: string, target: any | string = null) {
    this.write(6, target, msg)
  }

  public static error(msg: string, target: any | string = null) {
    this.write(5, target, msg)
  }

  public static debug(msg: string, target: any | string = null) {
    this.write(3, target, msg)
  }

  private static write(level: number, target: any | string, msg: string): void {
    try {
      easytier.writeAppLog(level, this.getTarget(target), msg)
    } catch (_) {
    }
  }

  private static getTarget(target: any): string {
    if (target == null) {
      return "Null";
    }
    if (typeof target === "string") {
      return target
    }
    const prefix = Reflect.get(target, LOG_LOCATE_METADATA)
    if (prefix) {
      return prefix
    } else if (target.prototype && Reflect.get(target.prototype, LOG_LOCATE_METADATA)) {
      return Reflect.get(target.prototype, LOG_LOCATE_METADATA) as string
    } else {
      return target.constructor.name
    }
  }
}
