import { rcp } from '@kit.RemoteCommunicationKit'
import Manager from '../../Manager'
import { SharedPeer } from '../config/ETConfig';
import Logger from '../Logger'

export async function updateSharedPeers(page: number = 1): Promise<void> {
  const request = new rcp.Request("https://uptime.easytier.cn/api/nodes?per_page=50&tags=%E5%9B%BD%E5%86%85&page="+page, 'GET');
  try {
    const session = rcp.createSession({
      headers: {
        "user-agent": "Mozilla/6.0 (XiaoLingTong; FrankHarmony 6.0)AppleWebKit/0.2 (FHTML, like Gecko)Chrome/0.1.0.3 Safari/0.2 ArkWeb/0.1.0.3 Mobile FrankBrowser/0.1.0.3"
      }
    });
    session.fetch(request).then((rep: rcp.Response) => {
      let obj = rep.toJSON()
      if (!obj) return;
      let success: boolean = obj["success"]
      if (!success) return;
      let data: object = obj["data"]
      let total: number = data["total"]
      let total_pages: number = data["total_pages"]
      let items: Array<object> = data["items"]
      Logger.info("[Manager] sharedPeers total peers:"+total)
      items.forEach((item: object) => {
        let peer = new SharedPeer(item)
        Manager.sharedPeers.add(peer)
      })
      if (total_pages > 1 && page == 1) {
        Logger.info("[Manager] sharedPeers total pages:"+total_pages)
        for (let index = 2; index <= total_pages; index++) {
          Logger.info("[Manager] read page "+index)
          updateSharedPeers(index)
        }
      }
    }).catch(() => {
      Logger.error(`[Manager] updateSharedPeers()::An unexpected error occurred.`);
    })
  } catch (e) {
    Logger.error(`[Manager] An unexpected error occurred. Code:${e.code},message:${e.message}`);
  }
return Promise.resolve()
}

export async function updateQQGroups(): Promise<void> {
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
      }else {
        // TODO discord && tg 跳转
      }
    }
  }
  Manager.qqgroups = texts;
  Logger.info("[Manager] Update QQ Groups:"+JSON.stringify(Manager.qqgroups))
  }).catch(() => {
    Logger.error(`[Manager] updateQQGroups()::An unexpected error occurred.`);
  })
  } catch (e) {
    Logger.error(`[Manager] An unexpected error occurred. Code:${e.code},message:${e.message}`);
  }
  return Promise.resolve()
}