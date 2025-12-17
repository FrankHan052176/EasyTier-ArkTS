import { BusinessError, commonEventManager, emitter } from '@kit.BasicServicesKit';
import { Logger } from './Logger';

export class EventHelper {
  private static bundleName = "top.frankhan.et4hm"

  public static commonListener(event: string, callback: (data: commonEventManager.CommonEventData) => void) {
    let subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [event],
      publisherBundleName: EventHelper.bundleName
    };
    let subscriber: commonEventManager.CommonEventSubscriber | null = null;
    commonEventManager.createSubscriber(subscribeInfo,
      (err: BusinessError, data: commonEventManager.CommonEventSubscriber) => {
        if (err) {
          return;
        }
        subscriber = data;
        commonEventManager.subscribe(subscriber, (err, data: commonEventManager.CommonEventData) => {
          if (err) {
            Logger.error(err.message, "EventHelper")
            return;
          }
          callback(data)
        })
      })
  }

  public static commonPublish(event: string) {
    commonEventManager.publish(event, () => {
    })
  }

  public static commonPublishCode(event: string, code: number) {
    commonEventManager.publish(event, {
      bundleName: EventHelper.bundleName,
      code: code
    }, () => {
    })
  }

  public static commonPublishData(event: string, data: string) {
    commonEventManager.publish(event, {
      bundleName: EventHelper.bundleName,
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
}