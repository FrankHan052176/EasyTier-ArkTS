export class ChangelogEntry {
  version: string;
  date: string;
  summary: string;
  changes: string[];

  constructor(version: string, date: string, summary: string, changes: string[]) {
    this.version = version;
    this.date = date;
    this.summary = summary;
    this.changes = changes;
  }
}

/**
 * 新版本记录追加在数组顶部。只写已经落地的用户可见变化，避免把计划中功能
 * 提前写成已完成状态。
 */
export const CHANGELOG_ENTRIES: ChangelogEntry[] = [
  new ChangelogEntry(
    '开发版',
    '2026-07-27',
    '完善版本更新提示、帮助信息与独立更新记录。',
    [
      '应用版本变化后自动展示一次更新日志。',
      '重构首次启动教程，移除“新版本特性”轮播。',
      '新增宽窄窗口自适应的更新日志页面。',
      '在教程工具栏和“关于与帮助”中增加更新日志入口。'
    ]
  ),
  new ChangelogEntry(
    '2.1.0',
    '2026-06-16',
    '完善运行方式、跨设备控制与稳定性。',
    [
      '新增跨设备控制能力与数据传输长时任务支持。',
      '加入音频保活、PC 任务栏保活和运行方案选择。',
      '修复 TOML 导入、路由表刷新以及实例停止阻塞问题。',
      '修复普通用户无法启用保活的问题。'
    ]
  )
];
