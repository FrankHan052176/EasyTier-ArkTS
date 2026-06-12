import { rcp } from '@kit.RemoteCommunicationKit';
import { AppManager } from '../../AppManager';
import { EventHelper } from '../../util/EventHelper';
import { Logger, LogLocate } from '../../shared/logging/Logger';
import { http } from '@kit.NetworkKit';

@LogLocate("WebUtil")
@ObservedV2
export class WebUtil {
  @Trace qqgroups: string[] = []

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

  public async getAppInfo(pkgName: string, callback: (name: string, icon: string) => void) {
    const httpRequest = http.createHttp();
    let response = await httpRequest.request("https://ddns.shenjack.top:10003/api/v0/apps/pkg_name/"+pkgName,
      {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'EasyTier',
          'Content-Type': 'application/json'
        }
      }
    )
    try {
      let obj: ESObject = JSON.parse(response.result!.toString())
      if (obj["success"]) {
        let data: ESObject = obj["data"]
        let info: ESObject = data["full_info"]
        let name = info["name"] as string
        let icon = info["icon_url"] as string
        callback(name, icon)
      }else {
        callback("未收录", "")
      }
    } catch (e) {
      Logger.error(`getAppInfo parse error: ${JSON.stringify(e)}`, this)
      callback("未收录", "")
    }
  }
}
