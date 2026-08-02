import { ValueType } from '@kit.ArkData';
import { AppManager } from '../../AppManager';
import { Logger, LogLocate } from '../../shared/logging/Logger';
import easytier from 'easytier-ohrs';
import { MemoryDiagnosticsService } from '../../services/runtime/MemoryDiagnosticsService';
import { BACKGROUND_KEEP_ALIVE_DATA_TRANSFER } from '../../types/runtime/BackgroundKeepAliveTypes';

const DEFAULT_SEQUENCE = 'Instances_0_0_2_1|Favorite_0_1_1_1|Logs_1_1_1_1|QQ_0_2_1_1|SharedPeers_1_2_1_1'

@LogLocate("UIState")
@ObservedV2
export class UIState {
  socketFilesDir: string = ''

  // --- 运行时状态 ---
  @Trace isStatusBar: boolean = false
  @Trace editingInstance: string | undefined
  @Trace notificationId: number | undefined = undefined

  // --- 持久化配置变量 (从 PreferencesUtil 迁移而来) ---
  @Trace favorite: string | undefined
  @Trace selected: string | undefined
  @Trace core_log: boolean = false
  @Trace debug_log: boolean = false
  @Trace raw_comp_sequence: string = DEFAULT_SEQUENCE
  @Trace vpn_routes: boolean = false
  @Trace dev: boolean = false
  @Trace force_global: boolean = true
  @Trace dns: string = ""
  @Trace noOldData: boolean = false
  @Trace holding_detector: boolean = false
  @Trace help2: boolean = false
  @Trace white_list: boolean = false
  @Trace vault_mode: boolean = false
  @Trace ask_dlp: boolean = false
  @Trace cloud_auto_sync: boolean = false
  @Trace background_keep_alive_mode: string = BACKGROUND_KEEP_ALIVE_DATA_TRANSFER

  // 记录启动时的初始状态，用于显示“重启后生效”
  inittedCoreLog: boolean = false

  setSocketFilesDir(filesDir: string) {
    this.socketFilesDir = filesDir
  }

  getSocketPath(socketName: string): string {
    return this.socketFilesDir.length > 0 ? `${this.socketFilesDir}/${socketName}` : socketName
  }

  // 自动持久化：监听所有配置变量的变化并保存
  @Monitor("favorite", "selected", "core_log", "debug_log", "raw_comp_sequence", "vpn_routes", 
           "dev", "force_global", "dns", "noOldData", "holding_detector", 
           "help2", "white_list", "vault_mode", "ask_dlp", "cloud_auto_sync",
           "background_keep_alive_mode")
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
        if (path === 'core_log' || path === 'debug_log') {
          easytier.configureLogManager(this.core_log, this.debug_log)
          if (path === 'debug_log') {
            MemoryDiagnosticsService.enableSystemLeakWatcher(this.debug_log)
          }
        }
      } catch (error) {
        Logger.error(`UIState: Failed to save ${path}.\n${error}`, this);
      }
    })
  }
}
