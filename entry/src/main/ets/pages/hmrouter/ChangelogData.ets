import { JSON } from '@kit.ArkTS';
import { AGCD_CHANGELOG_JSON } from '../../util/info/AgcdChangelog';

export enum ChangelogChannel {
  DEVELOPMENT = 'development',
  STABLE = 'stable'
}

export class ChangelogCategoryGroup {
  key: string;
  sourceName: string;
  repo: string;
  version: string;
  summary: string;
  items: string[];
  isUpstream: boolean;

  constructor(key: string, sourceName: string, repo: string, version: string,
    summary: string, items: string[], isUpstream: boolean) {
    this.key = key;
    this.sourceName = sourceName;
    this.repo = repo;
    this.version = version;
    this.summary = summary;
    this.items = items;
    this.isUpstream = isUpstream;
  }
}

export class ChangelogEntry {
  channel: ChangelogChannel;
  version: string;
  date: string;
  baseline: string;
  summary: string;
  changes: string[];
  downloadUrl: string;
  categories: ChangelogCategoryGroup[];

  constructor(channel: ChangelogChannel, version: string, date: string, baseline: string,
    summary: string, changes: string[], downloadUrl: string = '',
    categories: ChangelogCategoryGroup[] = []) {
    this.channel = channel;
    this.version = version;
    this.date = date;
    this.baseline = baseline;
    this.summary = summary;
    this.changes = changes;
    this.downloadUrl = downloadUrl;
    this.categories = categories;
  }
}

interface AgcdSourceSectionDto {
  triggerId?: string;
  sourceName?: string;
  repo?: string;
  version?: string;
  summary?: string;
  items?: string[];
}

interface AgcdChangelogDto {
  projectId?: string;
  versionName?: string;
  versionCode?: number;
  releaseDate?: string;
  channel?: string;
  summary?: string;
  mainProject?: AgcdSourceSectionDto;
  upstreams?: AgcdSourceSectionDto[];
  generatedAt?: number;
}

export const CHANGELOG_REVISION: string = '2026-08-11.2';
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
    ]
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
          entry.changes,
          DEVELOPMENT_DOWNLOAD_URL
        ));
        promoted = true;
      }
      continue;
    }
    entries.push(entry);
  }
  return entries;
}

function filterNonEmptyLines(items: string[] | undefined): string[] {
  const result: string[] = [];
  if (!items) {
    return result;
  }
  for (let i: number = 0; i < items.length; i++) {
    const line: string = (items[i] ?? '').trim();
    if (line.length > 0) {
      result.push(line);
    }
  }
  return result;
}

/**
 * 解析 AGCD 写入的分类更新日志：主项目变更与各上游触发器变更保持各自独立分组，不按时间混排。
 * 当未注入或内容为空时返回 undefined，调用方自动回退到仓库内置静态记录。
 */
export function parseAgcdChangelogEntry(rawJson: string, channelHint: string = 'development'): ChangelogEntry | undefined {
  const trimmed: string = rawJson.trim();
  if (trimmed.length === 0) {
    return undefined;
  }
  try {
    const dto: AgcdChangelogDto = JSON.parse(trimmed) as AgcdChangelogDto;
    const categories: ChangelogCategoryGroup[] = [];
    const flatChanges: string[] = [];

    if (dto.mainProject) {
      const mainItems: string[] = filterNonEmptyLines(dto.mainProject.items);
      const mainSummary: string = (dto.mainProject.summary ?? '').trim();
      if (mainItems.length > 0 || mainSummary.length > 0) {
        const mainSourceName: string = (dto.mainProject.sourceName ?? '').trim() || '主项目';
        categories.push(new ChangelogCategoryGroup(
          'main-project',
          mainSourceName,
          (dto.mainProject.repo ?? '').trim(),
          (dto.mainProject.version ?? '').trim(),
          mainSummary,
          mainItems,
          false
        ));
        for (let i: number = 0; i < mainItems.length; i++) {
          flatChanges.push(`[${mainSourceName}] ${mainItems[i]}`);
        }
      }
    }

    const upstreams: AgcdSourceSectionDto[] = dto.upstreams ?? [];
    for (let index: number = 0; index < upstreams.length; index++) {
      const upstream: AgcdSourceSectionDto = upstreams[index];
      const upstreamItems: string[] = filterNonEmptyLines(upstream.items);
      const upstreamSummary: string = (upstream.summary ?? '').trim();
      if (upstreamItems.length === 0 && upstreamSummary.length === 0) {
        continue;
      }
      const sourceName: string = (upstream.sourceName ?? '').trim() ||
        (upstream.triggerId ?? '').trim() || `上游依赖 ${index + 1}`;
      const key: string = (upstream.triggerId ?? '').trim() || `upstream-${index}`;
      categories.push(new ChangelogCategoryGroup(
        key,
        sourceName,
        (upstream.repo ?? '').trim(),
        (upstream.version ?? '').trim(),
        upstreamSummary,
        upstreamItems,
        true
      ));
      for (let j: number = 0; j < upstreamItems.length; j++) {
        flatChanges.push(`[${sourceName}] ${upstreamItems[j]}`);
      }
    }

    const topSummary: string = (dto.summary ?? '').trim();
    if (categories.length === 0 && topSummary.length === 0) {
      return undefined;
    }

    const isStable: boolean = dto.channel === 'stable' || channelHint === 'stable';
    const channel: ChangelogChannel = isStable ? ChangelogChannel.STABLE : ChangelogChannel.DEVELOPMENT;
    const versionName: string = (dto.versionName ?? '').trim();
    const versionText: string = versionName.length > 0 ? versionName : (isStable ? '正式版' : '开发版');
    const rawDate: string = (dto.releaseDate ?? '').trim();
    const dateText: string = isStable
      ? (rawDate.length > 0 ? rawDate : '当前构建')
      : (rawDate.length > 0 ? `更新至 ${rawDate}` : '当前开发构建');
    const versionCode: number = dto.versionCode ?? 0;
    const baselineText: string = versionCode > 0
      ? `构建号 ${versionCode}`
      : (isStable ? '当前正式发布' : '本地构建变更');
    const summaryText: string = topSummary.length > 0
      ? topSummary
      : `包含 ${categories.length} 个来源分类变更记录。`;

    return new ChangelogEntry(
      channel,
      versionText,
      dateText,
      baselineText,
      summaryText,
      flatChanges,
      isStable ? DEVELOPMENT_DOWNLOAD_URL : '',
      categories
    );
  } catch (_) {
    return undefined;
  }
}

export function resolveChangelogEntries(channelHint: string, appVersion: string, releaseDate: string,
  rawAgcdJson: string = AGCD_CHANGELOG_JSON): ChangelogEntry[] {
  const agcdEntry: ChangelogEntry | undefined = parseAgcdChangelogEntry(rawAgcdJson, channelHint);
  if (agcdEntry) {
    const result: ChangelogEntry[] = [agcdEntry];
    for (let i: number = 0; i < CHANGELOG_ENTRIES.length; i++) {
      const item: ChangelogEntry = CHANGELOG_ENTRIES[i];
      if (item.channel === ChangelogChannel.STABLE && item.version !== agcdEntry.version) {
        result.push(item);
      }
    }
    return result;
  }
  if (channelHint !== 'stable') {
    return CHANGELOG_ENTRIES;
  }
  return buildStableChangelogEntries(appVersion, releaseDate);
}

export function resolveChangelogRevision(rawAgcdJson: string = AGCD_CHANGELOG_JSON): string {
  const trimmed: string = rawAgcdJson.trim();
  if (trimmed.length === 0) {
    return CHANGELOG_REVISION;
  }
  try {
    const dto: AgcdChangelogDto = JSON.parse(trimmed) as AgcdChangelogDto;
    const versionName: string = (dto.versionName ?? '').trim();
    const versionCode: number = dto.versionCode ?? 0;
    const generatedAt: number = dto.generatedAt ?? 0;
    if (versionName.length > 0 || versionCode > 0 || generatedAt > 0) {
      return `agcd:${versionName}:${versionCode}:${generatedAt}`;
    }
  } catch (_) {
  }
  return CHANGELOG_REVISION;
}
