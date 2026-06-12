import { BusinessError, commonEventManager, emitter } from '@kit.BasicServicesKit';
import { Logger } from '../shared/logging/Logger';
import { APP_BUNDLE_NAME } from '../services/runtime/AbilityRuntimePolicy';

export class EventHelper {
  public static bundleName = APP_BUNDLE_NAME

  public static commonListener(event: string, callback: (data: commonEventManager.CommonEventData) => void): () => void {
    let subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined
    let cancelled: boolean = false
    let subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [event]
    };
    commonEventManager.createSubscriber(subscribeInfo,
      (err: BusinessError, data: commonEventManager.CommonEventSubscriber) => {
        if (err) {
          Logger.error(err.message, "EventHelper")
          return;
        }
        if (cancelled) {
          return
        }
        subscriber = data
        commonEventManager.subscribe(data, (err, data: commonEventManager.CommonEventData) => {
          if (err) {
            Logger.error(err.message, "EventHelper")
            return;
          }
          callback(data)
        })
      })
    return () => {
      cancelled = true
      if (!subscriber) {
        return
      }
      commonEventManager.unsubscribe(subscriber, () => {
      })
      subscriber = undefined
    }
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
