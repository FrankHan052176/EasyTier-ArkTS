import { ValueType } from '@kit.ArkData';
import { AppManager } from '../AppManager';
import { Logger, LogLocate } from '../util/Logger';

const DEFAULT_SEQUENCE = 'Instances_0_0_2_1|Favorite_0_1_1_1|Logs_1_1_1_1|QQ_0_2_1_1|SharedPeers_1_2_1_1'

@LogLocate("UIState")
@ObservedV2
export class UIState {
  // --- 运行时状态 ---
  @Trace isStatusBar: boolean = false
  @Trace editingInstance: string | undefined
  @Trace configUUIDNameMap: Map<string, string> = new Map
  @Trace notificationId: number | undefined = undefined

  // --- 持久化配置变量 (从 PreferencesUtil 迁移而来) ---
  @Trace favorite: string | undefined
  @Trace selected: string | undefined
  @Trace show_log: boolean = false
  @Trace raw_comp_sequence: string = DEFAULT_SEQUENCE
  @Trace vpn_routes: boolean = false
  @Trace dev: boolean = false
  @Trace force_global: boolean = true
  @Trace dns: string = ""
  @Trace noOldData: boolean = false
  @Trace holding_detector: boolean = false
  @Trace help2: boolean = false
  @Trace white_list: boolean = false
  @Trace git_core: boolean = true
  @Trace vault_mode: boolean = false
  @Trace ask_dlp: boolean = false
  @Trace ext_mode: boolean = false

  // 记录启动时的初始状态，用于显示“重启后生效”
  inittedLog: boolean = false
  inittedGitCore: boolean = false

  init() {
    // 逻辑已移动到 PreferencesUtil.init 中直接赋值，此处仅做二次校验或初始化
  }

  // 自动持久化：监听所有配置变量的变化并保存
  @Monitor("favorite", "selected", "show_log", "raw_comp_sequence", "vpn_routes", 
           "dev", "force_global", "dns", "noOldData", "holding_detector", 
           "help2", "white_list", "git_core", "vault_mode", "ask_dlp", "ext_mode")
  onStateChange(monitor: IMonitor) {
    if (AppManager.preference.isInit || !AppManager.preference.preferences) {
      return
    }

    monitor.dirty.forEach((path: string) => {
      try {
        let value = monitor.value(path)?.now as ValueType;
        Logger.debug(`UIState: Auto-saving ${path} = ${value}`, this);
        
        if (value === undefined) {
          AppManager.preference.preferences?.deleteSync(path);
        } else {
          AppManager.preference.preferences?.putSync(path, value as ValueType);
        }
        AppManager.preference.preferences?.flushSync();
      } catch (error) {
        Logger.error(`UIState: Failed to save ${path}.\n${error}`, this);
      }
    })
  }
}
