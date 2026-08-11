export enum ChangelogChannel {
  DEVELOPMENT = 'development',
  STABLE = 'stable'
}

export class ChangelogEntry {
  channel: ChangelogChannel;
  version: string;
  date: string;
  baseline: string;
  summary: string;
  changes: string[];
  downloadUrl: string;

  constructor(channel: ChangelogChannel, version: string, date: string, baseline: string,
    summary: string, changes: string[], downloadUrl: string = '') {
    this.channel = channel;
    this.version = version;
    this.date = date;
    this.baseline = baseline;
    this.summary = summary;
    this.changes = changes;
    this.downloadUrl = downloadUrl;
  }
}

export const CHANGELOG_REVISION: string = '2026-08-11.1';
export const DEVELOPMENT_DOWNLOAD_URL: string = 'https://appgallery.huawei.com/apptest/2MsGy1dzT1T';

/**
 * 新版本记录追加在数组顶部。只写已经落地的用户可见变化，避免把计划中功能
 * 提前写成已完成状态。
 */
export const CHANGELOG_ENTRIES: ChangelogEntry[] = [
  new ChangelogEntry(
    ChangelogChannel.DEVELOPMENT,
    '开发版',
    '更新至 2026-08-11',
    '基于 2.1.0 正式版累计',
    '持续完善跨设备管理、运行稳定性与配置体验。',
    [
      '新增近场跨设备控制台，可查看远端运行状态、一次性下发配置并启停实例。',
      '重构 VPN 与实例启动链，完善切网、路由更新和后台恢复，并降低后台负载。',
      '新增数据传输、音频和 PC 托盘等运行保持方案，按设备能力展示可用选项。',
      '优化配置编辑与存储链路，补全高级配置项，并支持复制配置与分享导入。',
      '修复流量速率统计、纯 IPv6 Peer 地址、路由刷新、实例停止阻塞和状态内存泄漏。',
      '新增可信三方应用的实例状态共享与按需启动接口。',
      '主页组件支持排序、隐藏和持久保存，完善教程、帮助、更新日志与运行诊断。'
    ],
    DEVELOPMENT_DOWNLOAD_URL
  ),
  new ChangelogEntry(
    ChangelogChannel.STABLE,
    '2.1.0',
    '2026-05-22',
    '上一次正式发布',
    '完善协议配置、云空间同步与旧配置兼容。',
    [
      '补全 TXT、HTTP(S) 与 SRV 协议配置，并展示对应的所选 Peer。',
      '新增云空间配置同步，并修复同步异常。',
      '兼容读取旧版配置，修复 TOML 导入后残留选择状态。',
      '状态页新增实例运行时长与内存占用信息。'
    ]
  )
];

export function buildStableChangelogEntries(version: string, releaseDate: string): ChangelogEntry[] {
  const entries: ChangelogEntry[] = [];
  let promoted: boolean = false;
  for (let index: number = 0; index < CHANGELOG_ENTRIES.length; index++) {
    const entry: ChangelogEntry = CHANGELOG_ENTRIES[index];
    if (entry.channel === ChangelogChannel.DEVELOPMENT) {
      if (!promoted) {
        entries.push(new ChangelogEntry(
          ChangelogChannel.STABLE,
          version,
          releaseDate.length > 0 ? releaseDate : entry.date.replace('更新至 ', ''),
          '当前正式发布',
          entry.summary,
          entry.changes
        ));
        promoted = true;
      }
      continue;
    }
    entries.push(entry);
  }
  return entries;
}
