import { rcp } from '@kit.RemoteCommunicationKit';
import { AppManager } from '../../AppManager';
import { EventHelper } from '../../util/EventHelper';
import { Logger, LogLocate } from '../../shared/logging/Logger';
import { startupMark } from '../runtime/StartupTrace';
import { http } from '@kit.NetworkKit';

const QQ_GROUPS_URL = 'https://easytier.cn/'
const QQ_GROUPS_CACHE_KEY = 'qq_groups_cache'
const QQ_GROUPS_CACHE_AT_KEY = 'qq_groups_cache_at'
/** 缓存有效期内不再联网刷新 */
const QQ_GROUPS_TTL_MS = 6 * 60 * 60 * 1000
/** 首帧之后再发起网络请求，避免 rcp 会话创建阻塞开屏 */
const QQ_GROUPS_FETCH_DELAY_MS = 1500

@LogLocate("WebUtil")
@ObservedV2
export class WebUtil {
  @Trace qqgroups: string[] = []
  private fetching: boolean = false
  private cacheLoaded: boolean = false
  private lastFetchAt: number = 0
  private pendingTimer: number = -1

  /** 读本地缓存，开屏直接渲染，不等网络 */
  private loadCachedGroups(): void {
    if (this.cacheLoaded) {
      return
    }
    this.cacheLoaded = true
    try {
      const raw = AppManager.preference.preferences?.getSync(QQ_GROUPS_CACHE_KEY, '')?.valueOf() as string ?? ''
      this.lastFetchAt = Number.parseInt(
        AppManager.preference.preferences?.getSync(QQ_GROUPS_CACHE_AT_KEY, '0')?.valueOf() as string ?? '0', 10) || 0
      if (raw.length > 0) {
        const cached = JSON.parse(raw) as string[]
        if (Array.isArray(cached) && cached.length > 0) {
          this.qqgroups = cached
        }
      }
    } catch (_) {
    }
  }

  private persistGroups(groups: string[]): void {
    try {
      AppManager.preference.preferences?.putSync(QQ_GROUPS_CACHE_KEY, JSON.stringify(groups))
      AppManager.preference.preferences?.putSync(QQ_GROUPS_CACHE_AT_KEY, this.lastFetchAt.toString())
      AppManager.preference.preferences?.flush()
    } catch (_) {
    }
  }

  private parseGroups(body: string): string[] {
    const pattern: RegExp = /<a\s+href="[^"]*"\s+target="_blank"\s+rel="noreferrer">([^<]*)<\/a>/gi;
    const texts: string[] = [];
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(body)) !== null) {
      if (match[1]) {
        const text = match[1].trim()
        if (!Number.isNaN(parseInt(text))) {
          texts.push(text);
        }
      }
    }
    return texts
  }

  private publishGroups(groups: string[]): void {
    // 必须发普通数组：@Trace 代理过的数组无法被 emitter 序列化，
    // 订阅端会收到空 payload（data.data 为 undefined）而崩溃。
    const plain: string[] = groups.slice()
    this.qqgroups = plain
    EventHelper.emitterPublish("update_qqgroups", {
      data: {
        groups: plain
      }
    })
  }

  /**
   * 入口：立即用缓存回填，联网刷新推迟到首帧之后异步执行。
   * 单飞 + TTL，卡片重复挂载不会重复发请求。
   */
  public updateQQGroups(): void {
    this.loadCachedGroups()
    if (this.qqgroups.length > 0) {
      this.publishGroups(this.qqgroups)
    }
    if (this.fetching || this.pendingTimer >= 0) {
      return
    }
    if (this.qqgroups.length > 0 && Date.now() - this.lastFetchAt < QQ_GROUPS_TTL_MS) {
      return
    }
    this.pendingTimer = setTimeout(() => {
      this.pendingTimer = -1
      void this.fetchQQGroups()
    }, QQ_GROUPS_FETCH_DELAY_MS)
  }

  private async fetchQQGroups(): Promise<void> {
    if (this.fetching) {
      return
    }
    this.fetching = true
    startupMark('qqgroups.fetch.begin')
    let session: rcp.Session | undefined = undefined
    try {
      session = rcp.createSession()
      const response = await session.fetch(new rcp.Request(QQ_GROUPS_URL, 'GET'))
      const texts = this.parseGroups(response.toString() ?? '')
      this.lastFetchAt = Date.now()
      if (texts.length > 0) {
        this.publishGroups(texts)
        this.persistGroups(texts)
      }
      Logger.debug(`Update QQ Groups: ${JSON.stringify(texts)}`, this)
    } catch (error) {
      Logger.error(`updateQQGroups failed: ${JSON.stringify(error)}`, this);
    } finally {
      try {
        session?.close()
      } catch (_) {
      }
      this.fetching = false
      startupMark('qqgroups.fetch.end')
    }
  }

  public async getAppInfo(pkgName: string, callback: (name: string, icon: string) => void) {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request("https://ddns.shenjack.top:10003/api/v0/apps/pkg_name/" + pkgName,
        {
          method: http.RequestMethod.GET,
          header: {
            'User-Agent': 'EasyTier',
            'Content-Type': 'application/json'
          }
        }
      )
      const obj: ESObject = JSON.parse(response.result!.toString())
      if (obj["success"]) {
        const data: ESObject = obj["data"]
        const info: ESObject = data["full_info"]
        callback(info["name"] as string, info["icon_url"] as string)
      } else {
        callback("未收录", "")
      }
    } catch (e) {
      Logger.error(`getAppInfo failed: ${JSON.stringify(e)}`, this)
      callback("未收录", "")
    } finally {
      httpRequest.destroy()
    }
  }
}
