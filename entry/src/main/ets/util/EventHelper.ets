import { BusinessError, commonEventManager, emitter } from '@kit.BasicServicesKit';
import { Logger } from '../shared/logging/Logger';

export class EventHelper {
  public static bundleName = "top.frankhan.easytier"

  public static commonListener(event: string, callback: (data: commonEventManager.CommonEventData) => void) {
    let subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [event]
    };
    commonEventManager.createSubscriber(subscribeInfo,
      (err: BusinessError, data: commonEventManager.CommonEventSubscriber) => {
        if (err) {
          Logger.error(err.message, "EventHelper")
          return;
        }
        commonEventManager.subscribe(data, (err, data: commonEventManager.CommonEventData) => {
          if (err) {
            Logger.error(err.message, "EventHelper")
            return;
          }
          callback(data)
        })
      })
  }

  public static commonPublish(event: string) {
    commonEventManager.publish(event, () => {})
  }

  public static commonPublishData(event: string, data: string) {
    commonEventManager.publish(event, {
      data: data
    }, () => {
    })
  }

  public static commonPublishCallback(event: string, callback: () => void) {
    commonEventManager.publish(event, callback)
  }

  public static emitterListener(event: string, callback: Callback<emitter.EventData>) {
    emitter.on(event, callback)
  }

  public static emitterPublish(event: string, data: emitter.EventData | undefined = undefined) {
    emitter.emit(event, data)
  }

  public static emitterOff(event: string, callback?: Callback<emitter.EventData>) {
    if (callback) {
      emitter.off(event, callback)
      return
    }
    emitter.off(event)
  }
}
