import { AppManager } from '../../AppManager'
import { logColor } from '../../util/Conversion'
import { LightModifier } from '../../class/modifier/SymbolLight'
import { StackLightModifier } from '../../class/modifier/BackgroundLight'
import { LogDataSource } from '../../class/data_source/LogDataSource'
import { hdsEffect, hdsMaterial, HdsNavigation, HdsNavigationTitleMode,
  IconStyleMode,
  TitleBarStyleOptions } from '@kit.UIDesignKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { LengthMetrics } from '@kit.ArkUI'
import { LogFileEntry } from '../../types/logging/LogFileTypes'

function formatLogTime(raw: number): string {
  if (raw <= 0) {
    return '未知时间'
  }
  const date = new Date(raw)
  const yyyy = date.getFullYear()
  const mm = String(date.getMonth() + 1).padStart(2, '0')
  const dd = String(date.getDate()).padStart(2, '0')
  const hh = String(date.getHours()).padStart(2, '0')
  const mi = String(date.getMinutes()).padStart(2, '0')
  return `${yyyy}-${mm}-${dd} ${hh}:${mi}`
}

function formatBytes(size: number): string {
  if (size >= 1024 * 1024) {
    return `${(size / 1024 / 1024).toFixed(1)} MB`
  }
  if (size >= 1024) {
    return `${(size / 1024).toFixed(1)} KB`
  }
  return `${size} B`
}

function logDisplayText(log: string): string {
  const level = Number.parseInt(log.charAt(0))
  return Number.isNaN(level) ? log : log.substring(1)
}

function logNavTitleStyle(): TitleBarStyleOptions {
  if (deviceInfo.distributionOSApiVersion >= 60100 && hdsMaterial.getSystemMaterialTypes().length > 0) {
    return {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
        blurEffectiveStartOffset: LengthMetrics.vp(0),
        blurEffectiveEndOffset: LengthMetrics.vp(20),
      },
      originalStyle: {
        contentStyle: {
          titleStyle: {
            mainTitleColor: $r("sys.color.font_primary"),
            subTitleColor: $r("sys.color.font_secondary")
          },
          menuStyle: {
            iconColor: $r("sys.color.font_primary")
          },
          backIconStyle: {
            iconColor: $r("sys.color.font_primary")
          }
        }
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    }
  } else {
    return {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
        blurEffectiveStartOffset: LengthMetrics.vp(0),
        blurEffectiveEndOffset: LengthMetrics.vp(20),
      },
      originalStyle: {
        contentStyle: {
          titleStyle: {
            mainTitleColor: $r("sys.color.font_primary"),
            subTitleColor: $r("sys.color.font_secondary")
          },
          menuStyle: {
            iconColor: $r("sys.color.font_primary"),
            backgroundColor: $r("sys.color.background_primary")
          },
          backIconStyle: {
            iconColor: $r("sys.color.font_primary"),
            backgroundColor: $r("sys.color.background_primary")
          }
        }
      }
    }
  }
}

class FileLogDataSource implements IDataSource {
  private lines: string[] = []
  private listeners: DataChangeListener[] = []

  setLines(lines: string[]): void {
    this.lines = lines
    this.notifyDataReload()
  }

  totalCount(): number {
    return this.lines.length
  }

  getData(index: number): string {
    return this.lines[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener)
    if (index >= 0) {
      this.listeners.splice(index, 1)
    }
  }

  private notifyDataReload(): void {
    this.listeners.forEach((listener) => {
      listener.onDataReloaded()
    })
  }
}

@ComponentV2
struct LogCenterSheet {
  @Local logFiles: LogFileEntry[] = []
  @Local selectedLogFileName: string = ''
  @Local selectedFileLines: string[] = []
  private fileLogDataSource: FileLogDataSource = new FileLogDataSource()
  @Event onClose: () => void = () => {}

  @Computed
  get appCount(): number {
    return AppManager.easytier.appLogs.totalCount()
  }

  @Computed
  get selectedTitle(): string {
    if (this.selectedLogFileName.length <= 0) {
      return `实时缓存 · ${this.appCount} 条`
    }
    const log = this.findLogFile(this.selectedLogFileName)
    return log ? `${this.logFileLabel(log)} · ${this.selectedFileLines.length} 条 · ${this.shortFileName(log.fileName)}` :
      `日志文件 · ${this.selectedFileLines.length} 条`
  }

  aboutToAppear(): void {
    this.refreshLogFiles()
    const target = this.chooseInitialLogFile()
    this.selectLogFile(target)
  }

  private refreshLogFiles(): void {
    this.logFiles = AppManager.easytier.listLogFiles()
  }

  private chooseInitialLogFile(): string {
    const active = this.logFiles.find((log: LogFileEntry) => log.active)
    if (active) {
      return active.fileName
    }
    return this.logFiles.length > 0 ? this.logFiles[0].fileName : ''
  }

  private selectLogFile(fileName: string): void {
    this.selectedLogFileName = fileName
    this.selectedFileLines = fileName.length > 0 ? AppManager.easytier.readLogFileLines(fileName) : []
    this.fileLogDataSource.setLines(this.selectedFileLines)
  }

  private findLogFile(fileName: string): LogFileEntry | undefined {
    return this.logFiles.find((log: LogFileEntry) => log.fileName === fileName)
  }

  private shortFileName(fileName: string): string {
    if (fileName.length <= 24) {
      return fileName
    }
    return fileName.substring(fileName.length - 24)
  }

  private logFileLabel(log: LogFileEntry): string {
    return log.active ? '当前启动日志' : log.displayName
  }

  private logFileSubtitle(log: LogFileEntry): string {
    return `${formatLogTime(log.modifiedMs)} · ${formatBytes(log.sizeBytes)}`
  }

  @Builder
  LogSelectorBar() {
    Scroll() {
      Row() {
        this.LogSelectorChip('实时缓存', `${this.appCount} 条`, '')
        ForEach(this.logFiles, (log: LogFileEntry) => {
          this.LogSelectorChip(this.logFileLabel(log), this.logFileSubtitle(log), log.fileName)
        }, (log: LogFileEntry) => log.fileName)
      }
      .padding({ left: 10, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(76)
    .backgroundColor($r("sys.color.background_secondary"))
  }

  @Builder
  LogSelectorChip(title: string, subtitle: string, fileName: string) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selectedLogFileName === fileName ? $r('sys.color.interactive_active') : $r('sys.color.font_primary'))
        .maxLines(1)
      Text(subtitle)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .height(54)
    .constraintSize({ minWidth: 112, maxWidth: 188 })
    .padding({ left: 12, right: 12 })
    .borderRadius(14)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .border({
      width: this.selectedLogFileName === fileName ? 1 : 0,
      color: this.selectedLogFileName === fileName ? $r('sys.color.interactive_active') : Color.Transparent
    })
    .margin({ left: 6, right: 2, top: 10, bottom: 8 })
    .onClick(() => {
      this.selectLogFile(fileName)
    })
  }

  @Builder
  LogList(list: LogDataSource) {
    List() {
      if (list.totalCount() > 0) {
        LazyForEach(list, (msg: string) => {
          ListItem() {
            Text(logDisplayText(msg))
              .fontSize(12)
              .fontColor(logColor(msg))
              .fontFamily('Monospace')
              .width('100%')
              .copyOption(CopyOptions.LocalDevice)
              .padding({ top: 2, bottom: 2 })
          }
        })
      } else {
        ListItem() {
          this.EmptyLogView()
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .alignListItem(ListItemAlign.Start)
    .padding({
      left: 16,
      right: 16,
      top: 8,
      bottom: 8
    })
  }

  @Builder
  FileLogList(dataSource: FileLogDataSource) {
    List() {
      if (dataSource.totalCount() > 0) {
        LazyForEach(dataSource, (msg: string) => {
          ListItem() {
            Text(logDisplayText(msg))
              .fontSize(12)
              .fontColor(logColor(msg))
              .fontFamily('Monospace')
              .width('100%')
              .copyOption(CopyOptions.LocalDevice)
              .padding({ top: 2, bottom: 2 })
          }
        }, (_msg: string, index: number) => `${this.selectedLogFileName}-${index}`)
      } else {
        ListItem() {
          this.EmptyLogView()
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .alignListItem(ListItemAlign.Start)
    .padding({
      left: 16,
      right: 16,
      top: 8,
      bottom: 8
    })
  }

  @Builder
  EmptyLogView() {
    Column() {
      SymbolGlyph($r('sys.symbol.doc_plaintext_and_checkmark'))
        .fontSize(48)
        .fontColor([$r('sys.color.font_secondary')])
      Text("暂无日志")
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .margin({ top: 8 })
    }
    .width("100%")
    .height(200)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    HdsNavigation() {
      Column() {
        this.LogSelectorBar()
        Text(this.selectedTitle)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 2 })
        if (this.selectedLogFileName.length <= 0) {
          this.LogList(AppManager.easytier.appLogs)
        } else {
          this.FileLogList(this.fileLogDataSource)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r("sys.color.background_secondary"))
    }
    .height('100%')
    .width('100%')
    .backgroundColor($r("sys.color.background_secondary"))
    .titleBar({
      style: logNavTitleStyle(),
      content: {
        title: {
          mainTitle: "日志中心"
        },
        menu: {
          value: [{
            content: {
              icon: $r('sys.symbol.xmark'),
              type: IconStyleMode.NORMAL,
              action: () => {
                this.onClose()
              },
            }
          }]
        },
      },
      enableComponentSafeArea: true
    })
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .hideTitleBar(false)
    .height('100%')
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

@ComponentV2
export struct Logs {
  @Local showSheet: boolean = false
  @Local selectedLogIndex: number = 0
  @Local logFiles: LogFileEntry[] = []
  @Local selectedLogFileName: string = ''
  @Local selectedFileLines: string[] = []
  @Local lightMod: LightModifier = new LightModifier($r('sys.color.font_primary'))
  @Local bgMode: StackLightModifier = new StackLightModifier()
  @Consumer("w") w: number = 1
  @Consumer("h") h: number = 1

  @Computed
  get appCount(): number {
    return AppManager.easytier.appLogs.totalCount()
  }

  @Computed
  get totalCount(): number {
    return this.appCount
  }

  @Computed
  get latestLog(): string {
    if (this.appCount > 0) {
      return AppManager.easytier.appLogs.getData(this.appCount - 1)
    }
    return "暂无日志数据"
  }

  navTitleStyle(): TitleBarStyleOptions {
    if (deviceInfo.distributionOSApiVersion >= 60100 && hdsMaterial.getSystemMaterialTypes().length > 0) {
      return {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20),
        },
        originalStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r("sys.color.font_primary"),
              subTitleColor: $r("sys.color.font_secondary")
            },
            menuStyle: {
              iconColor: $r("sys.color.font_primary")
            },
            backIconStyle: {
              iconColor: $r("sys.color.font_primary")
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    }else {
      return {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20),
        },
        originalStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r("sys.color.font_primary"),
              subTitleColor: $r("sys.color.font_secondary")
            },
            menuStyle: {
              iconColor: $r("sys.color.font_primary"),
              backgroundColor: $r("sys.color.background_primary")
            },
            backIconStyle: {
              iconColor: $r("sys.color.font_primary"),
              backgroundColor: $r("sys.color.background_primary")
            }
          }
        }
      }
    }
  }

  private refreshLogFiles(): void {
    this.logFiles = AppManager.easytier.listLogFiles()
  }

  private chooseInitialLogFile(): string {
    const active = this.logFiles.find((log: LogFileEntry) => log.active)
    if (active) {
      return active.fileName
    }
    return this.logFiles.length > 0 ? this.logFiles[0].fileName : ''
  }

  private selectLogFile(fileName: string): void {
    this.selectedLogFileName = fileName
    this.selectedFileLines = fileName.length > 0 ? AppManager.easytier.readLogFileLines(fileName) : []
  }

  private selectLogIndex(index: number): void {
    const safeIndex = Math.max(0, Math.min(index, this.logFiles.length))
    this.selectedLogIndex = safeIndex
    if (safeIndex <= 0) {
      this.selectLogFile('')
      return
    }
    const log = this.logFiles[safeIndex - 1]
    this.selectLogFile(log ? log.fileName : '')
  }

  private openLogSheet(): void {
    this.showSheet = true
  }

  private logFileLabel(log: LogFileEntry): string {
    return log.active ? '当前启动日志' : log.displayName
  }

  private logFileSubtitle(log: LogFileEntry): string {
    return `${formatLogTime(log.modifiedMs)} · ${formatBytes(log.sizeBytes)}`
  }

  @Builder
  LogSheetContent() {
    LogCenterSheet({
      onClose: (): void => {
        this.showSheet = false
      }
    })
  }

  @Builder
  LogSelectorBar() {
    Scroll() {
      Row() {
        this.LogSelectorChip('实时缓存', `${this.appCount} 条`, 0)
        ForEach(this.logFiles, (log: LogFileEntry, index: number) => {
          this.LogSelectorChip(this.logFileLabel(log), this.logFileSubtitle(log), index + 1)
        }, (log: LogFileEntry) => log.fileName)
      }
      .padding({ left: 10, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(76)
    .backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  LogSelectorChip(title: string, subtitle: string, index: number) {
    if (this.selectedLogIndex === index) {
      this.SelectedLogSelectorChip(title, subtitle, index)
    } else {
      this.UnselectedLogSelectorChip(title, subtitle, index)
    }
  }

  @Builder
  SelectedLogSelectorChip(title: string, subtitle: string, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.interactive_active'))
        .maxLines(1)
      Text(subtitle)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .height(54)
    .constraintSize({ minWidth: 112, maxWidth: 188 })
    .padding({ left: 12, right: 12 })
    .borderRadius(14)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .border({
      width: 1,
      color: $r('sys.color.interactive_active')
    })
    .margin({ left: 6, right: 2, top: 10, bottom: 8 })
    .onClick(() => {
      this.selectLogIndex(index)
    })
  }

  @Builder
  UnselectedLogSelectorChip(title: string, subtitle: string, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
      Text(subtitle)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .height(54)
    .constraintSize({ minWidth: 112, maxWidth: 188 })
    .padding({ left: 12, right: 12 })
    .borderRadius(14)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .border({
      width: 0,
      color: Color.Transparent
    })
    .margin({ left: 6, right: 2, top: 10, bottom: 8 })
    .onClick(() => {
      this.selectLogIndex(index)
    })
  }

  @Builder
  LogList(list: LogDataSource) {
    List() {
      if (list.totalCount() > 0) {
        LazyForEach(list, (msg: string) => {
          ListItem() {
            Text(logDisplayText(msg))
              .fontSize(12)
              .fontColor(logColor(msg))
              .fontFamily('Monospace')
              .width('100%')
              .copyOption(CopyOptions.LocalDevice)
              .padding({ top: 2, bottom: 2 })
          }
        })
      } else {
        ListItem() {
          Column() {
            SymbolGlyph($r('sys.symbol.doc_plaintext_and_checkmark'))
              .fontSize(48)
              .fontColor([$r('sys.color.font_secondary')])
            Text("暂无日志")
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ top: 8 })
          }
          .width("100%")
          .height(200)
          .justifyContent(FlexAlign.Center)
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .alignListItem(ListItemAlign.Start)
    .padding({
      left: 16,
      right: 16,
      top: 8,
      bottom: 8
    })
  }

  @Builder
  FileLogList(lines: string[]) {
    List() {
      if (lines.length > 0) {
        ForEach(lines, (msg: string, index: number) => {
          ListItem() {
            Text(logDisplayText(msg))
              .fontSize(12)
              .fontColor(logColor(msg))
              .fontFamily('Monospace')
              .width('100%')
              .copyOption(CopyOptions.LocalDevice)
              .padding({ top: 2, bottom: 2 })
          }
        }, (_msg: string, index: number) => index.toString())
      } else {
        ListItem() {
          Column() {
            SymbolGlyph($r('sys.symbol.doc_plaintext_and_checkmark'))
              .fontSize(48)
              .fontColor([$r('sys.color.font_secondary')])
            Text("暂无日志")
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ top: 8 })
          }
          .width("100%")
          .height(200)
          .justifyContent(FlexAlign.Center)
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .alignListItem(ListItemAlign.Start)
    .padding({
      left: 16,
      right: 16,
      top: 8,
      bottom: 8
    })
  }

  @Builder
  point() {
    Column()
      .size({ width: 1, height: 1 })
      .attributeModifier(this.lightMod)
  }

  @Builder
  Logo() {
    SymbolGlyph($r('sys.symbol.list_bullet_square'))
      .fontSize(24)
      .fontColor([$r('sys.color.font_primary')])
      .overlay(this.point, {
        align: Alignment.Center
      })
  }

  @Builder
  Size1x1() {
    Column() {
      Row() {
        this.Logo()
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      Column() {
        Text(this.totalCount.toString())
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text("日志总数")
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.openLogSheet()
      })
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  // --- 2x1 布局 ---
  @Builder
  Size2x1() {
    Column() {
      Row() {
        this.Logo()
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 8 })

      Row() {
        Column() {
          Text(this.totalCount.toString())
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))

          Text("日志总数")
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.openLogSheet()
        })

        Row({ space: 16 }) {
          this.MiniStatItem($r('sys.symbol.house'), 0)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  MiniStatItem(icon: Resource, tabIdx: number) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([$r('sys.color.font_secondary')])
      Text(this.appCount.toString())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
    }
    .onClick(() => {
      this.openLogSheet()
    })
  }

  // --- 1x2 布局 ---
  @Builder
  Size1x2() {
    Column() {
      Row() {
        this.Logo()
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 8 })

      Column({ space: 8 }) {
        this.ListStatItem("运行日志", this.appCount, $r('sys.symbol.house'), 0)
      }
      .justifyContent(FlexAlign.Center)
      .height('100%')
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  ListStatItem(name: string, count: number, icon: Resource, tabIdx: number) {
    Row() {
      Row({ space: 8 }) {
        SymbolGlyph(icon)
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
        Text(name)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
      }

      Text(count.toString())
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding(8)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(8)
    .onClick(() => {
      this.openLogSheet()
    })
  }

  // --- 2x2 布局 ---
  @Builder
  Size2x2() {
    Column() {
      Row() {
        this.Logo()

        Blank()

        Text("Total: " + this.totalCount)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      Row({ space: 8 }) {
        this.CardStatItem("运行日志", $r('sys.symbol.house'), 0)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 12 })

      Column() {
        Text("最新日志")
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ bottom: 4 })
        Text(logDisplayText(this.latestLog))
          .fontSize(12)
          .fontColor($r('sys.color.font_primary'))
          .fontFamily('Monospace')
          .maxLines(5)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding(8)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(8)
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.TopStart)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  CardStatItem(name: string, icon: Resource, tabIdx: number) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([$r('sys.color.interactive_active')])
        .margin({ bottom: 4 })
      Text(this.appCount.toString())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      Text(name)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
    }
    .layoutWeight(1)
    .height(90)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(12)
    .onClick(() => {
      this.openLogSheet()
    })
  }

  build() {
    Stack() {
      // 适配不同尺寸
      if (this.w === 1 && this.h === 1) {
        this.Size1x1()
      } else if (this.w === 2 && this.h === 1) {
        this.Size2x1()
      } else if (this.w === 1 && this.h === 2) {
        this.Size1x2()
      } else {
        this.Size2x2()
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(18)
    .bindSheet($$this.showSheet, this.LogSheetContent(), {
      height: SheetSize.LARGE,
      preferType: SheetType.CENTER,
      showClose: false,
      dragBar: false
    })
    .attributeModifier(this.bgMode)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .shadow({
      radius: 7,
      color: '#1F000000'
    })
    .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
    }).buildEffect())
  }
}
