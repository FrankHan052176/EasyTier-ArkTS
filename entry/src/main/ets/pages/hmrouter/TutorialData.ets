export class TutorialAction {
  title: string;
  description: string;

  constructor(title: string, description: string) {
    this.title = title;
    this.description = description;
  }
}

export class TutorialStep {
  id: string;
  shortTitle: string;
  title: string;
  subtitle: string;
  summary: string;
  actions: TutorialAction[];

  constructor(
    id: string,
    shortTitle: string,
    title: string,
    subtitle: string,
    summary: string,
    actions: TutorialAction[]
  ) {
    this.id = id;
    this.shortTitle = shortTitle;
    this.title = title;
    this.subtitle = subtitle;
    this.summary = summary;
    this.actions = actions;
  }
}

/**
 * 教程只记录长期稳定的核心任务。版本变化统一维护在 ChangelogData.ets，
 * 避免每次发布都把首次使用流程改成“新功能广告”。
 */
export const TUTORIAL_STEPS: TutorialStep[] = [
  new TutorialStep(
    'join',
    '接入网络',
    '先接入一个网络',
    '创建配置，或从已有配置开始',
    'EasyTier 支持新建配置，也支持通过剪贴板、系统分享和 TOML 文件导入。',
    [
      new TutorialAction('新建配置', '填写网络名称、密钥与虚拟地址，保存后即可使用。'),
      new TutorialAction('三路导入', '从剪贴板、系统分享或 TOML 文件导入已有配置。'),
      new TutorialAction('启动前检查', '确认网络名、密钥和虚拟地址属于目标网络。')
    ]
  ),
  new TutorialStep(
    'run',
    '运行状态',
    '启动并确认运行状态',
    '连接后先确认实例与流量是否正常',
    '网络页会集中呈现正在运行的配置、已接入的控制台和整体上下行。',
    [
      new TutorialAction('启动配置', '在网络页选择已保存的配置并启动实例。'),
      new TutorialAction('查看当前状态', '运行列表会显示配置实例、连接状态和控制台。'),
      new TutorialAction('进入实例详情', '查看节点、NAT、路由以及实时上下行数据。')
    ]
  ),
  new TutorialStep(
    'remote',
    '跨设备控制',
    '从另一台设备进行控制',
    '集中查看与管理受信任设备上的 EasyTier',
    '跨设备控制用于查看远端配置与运行状态，并在确认目标设备后执行操作。',
    [
      new TutorialAction('发现设备', '从跨设备控制入口选择当前可用的目标设备。'),
      new TutorialAction('核对目标', '操作前确认设备名称、实例名称与当前状态。'),
      new TutorialAction('按需断开', '完成查看或控制后，可以随时返回或断开连接。')
    ]
  ),
  new TutorialStep(
    'tools',
    '高级工具',
    '需要时再使用高级工具',
    '排障、策略与日常管理各有明确入口',
    '日志用于定位问题；DNS、路由表和黑白名单用于调整网络行为。',
    [
      new TutorialAction('日志排查', '从工具栏打开日志，查看运行过程与异常信息。'),
      new TutorialAction('网络策略', '按需调整 DNS、路由表控制以及黑白名单。'),
      new TutorialAction('日常管理', '保活、云空间、收藏、配置分享都可独立使用。')
    ]
  )
];
