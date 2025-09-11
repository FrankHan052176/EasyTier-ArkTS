import { BusinessError, commonEventManager, emitter } from "@kit.BasicServicesKit";
import Logger from "./Logger";

export class EventHelper {
  private bundleName = "top.frankhan.et4hm"
  public commonListener(event: string, callback: (data: commonEventManager.CommonEventData) => void) {
    let subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [event],
      publisherBundleName: this.bundleName
    };
    let subscriber: commonEventManager.CommonEventSubscriber | null = null;
    commonEventManager.createSubscriber(subscribeInfo, (err: BusinessError, data: commonEventManager.CommonEventSubscriber) => {
      if (err) {return;}
      subscriber = data;
      commonEventManager.subscribe(subscriber, (err, data:commonEventManager.CommonEventData) => {
        if (err) {
          Logger.error(err.message)
          return;
        }
        callback(data)
      })
    })
  }

  public commonPublish(event: string) {
    commonEventManager.publish(event,()=>{})
  }

  public commonPublishCode(event: string, code: number) {
    commonEventManager.publish(event,{
      bundleName: this.bundleName,
      code: code
    },()=>{})
  }

  public commonPublishData(event: string, data: string) {
    commonEventManager.publish(event,{
      bundleName: this.bundleName,
      data: data
    },()=>{})
  }

  public commonPublishCallback(event: string, callback: () => void) {
    commonEventManager.publish(event,callback)
  }

  public emitterListener(event: string, callback: Callback<emitter.EventData>) {
    emitter.on(event, callback)
  }

  public emitterPublish(event: string, data: emitter.EventData | undefined = undefined) {
    emitter.emit(event, data)
  }
}

export default new EventHelper()