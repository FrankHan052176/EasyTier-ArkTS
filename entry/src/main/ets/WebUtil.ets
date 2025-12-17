import { rcp } from '@kit.RemoteCommunicationKit';
import { AppManager } from './AppManager';
import { EventHelper } from './util/EventHelper';
import { Logger, LogLocate } from './util/Logger';

@LogLocate("WebUtil")
@ObservedV2
export class WebUtil {
  @Trace qqgroups: string[] = []

  public async updateSharedPeers(page: number = 1): Promise<void> {
    const request =
      new rcp.Request("https://uptime.easytier.cn/api/nodes?per_page=50&tags=%E5%9B%BD%E5%86%85&page=" + page, 'GET');
    try {
      const session = rcp.createSession({
        headers: {
          "user-agent": "Mozilla/6.0 (XiaoLingTong; FrankHarmony 6.0)AppleWebKit/0.2 (FHTML, like Gecko)Chrome/0.1.0.3 Safari/0.2 ArkWeb/0.1.0.3 Mobile FrankBrowser/0.1.0.3"
        }
      });
      session.fetch(request).then((rep: rcp.Response) => {
        let obj = rep.toJSON()
        if (!obj) {
          return;
        }
        let success: boolean = obj["success"]
        if (!success) {
          return;
        }
        let data: object = obj["data"]
        let total: number = data["total"]
        let total_pages: number = data["total_pages"]
        let items: Array<object> = data["items"]
        Logger.info("sharedPeers total peers:" + total, this)
        items.forEach((item: object) => {

        })
        if (total_pages > 1 && page == 1) {
          Logger.info("sharedPeers total pages:" + total_pages, this)
          for (let index = 2; index <= total_pages; index++) {
            Logger.info("read page " + index, this)
            this.updateSharedPeers(index)
          }
        }
      }).catch(() => {
        Logger.error(`updateSharedPeers()::An unexpected error occurred.`, this);
      })
    } catch (e) {
      Logger.error(`An unexpected error occurred. Code:${e.code},message:${e.message}`, this);
    }
    return Promise.resolve()
  }

  public async updateQQGroups() {
    const request = new rcp.Request("https://easytier.cn/", 'GET');
    try {
      const session = rcp.createSession();
      session.fetch(request).then((rep: rcp.Response) => {
        const pattern: RegExp = /<a\s+href="[^"]*"\s+target="_blank"\s+rel="noreferrer">([^<]*)<\/a>/gi;
        const texts: string[] = [];

        let match: RegExpExecArray | null;
        while ((match = pattern.exec(rep.toString()!)) !== null) {
          if (match[1]) {
            let text = match[1].trim()
            if (!Number.isNaN(parseInt(text))) {
              texts.push(text);
            } else {
              // TODO discord && tg 跳转
            }
          }
        }
        AppManager.web.qqgroups = texts
        Logger.debug("Update QQ Groups:" + JSON.stringify(AppManager.web.qqgroups), WebUtil)
        EventHelper.emitterPublish("update_qqgroups", {
          data: {
            groups: texts
          }
        })
      }).catch(() => {
        Logger.error(`updateQQGroups()::An unexpected error occurred.`, WebUtil);
      })
    } catch (e) {
      Logger.error(`An unexpected error occurred. Code:${e.code},message:${e.message}`, WebUtil);
    }
  }
}