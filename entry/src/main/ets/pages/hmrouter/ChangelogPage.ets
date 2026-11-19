import { HMRouter } from '@hadss/hmrouter';
import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { AppManager } from '../../AppManager';
import { sendToast } from '../../ToastUtil';
import { WindowUtil } from '../../WindowUtil';
import { APP_CHANNEL, APP_RELEASE_DATE, APP_VERSION } from '../../util/info/BuildTime';
import {
  ChangelogCategoryGroup,
  ChangelogChannel,
  ChangelogEntry,
  resolveChangelogEntries
} from './ChangelogData';
import { pageTitleBarStyle } from './HdsPageStyle';

const MAX_CONTENT_WIDTH: number = 760;

@ComponentV2
struct ChangelogChangeRow {
  @Param @Require change: string;

  build(): void {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.checkmark_circle'))
        .fontSize(19)
        .fontColor([$r('sys.color.brand')])

      Text(this.change)
        .layoutWeight(1)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
  }
}

@ComponentV2
struct ChangelogCategorySection {
  @Param @Require group: ChangelogCategoryGroup;

  build(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.group.isUpstream ? '上游变更' : '主项目')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.group.isUpstream ? $r('sys.color.font_secondary') : $r('sys.color.brand'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(8)
          .backgroundColor($r('sys.color.comp_background_secondary'))

        Text(this.group.sourceName)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.group.version.length > 0) {
          Text(this.group.version)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
        }
      }
      .width('100%')

      if (this.group.repo.length > 0) {
        Text(this.group.repo)
          .width('100%')
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.group.summary.length > 0) {
        Text(this.group.summary)
          .width('100%')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(3)
      }

      if (this.group.items.length > 0) {
        Column() {
          ForEach(this.group.items, (item: string, idx: number) => {
            ChangelogChangeRow({ change: item })
          }, (item: string, idx: number): string => `${this.group.key}-${idx}-${item}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(14)
  }
}

@ComponentV2
struct ChangelogEntryCard {
  @Param @Require entry: ChangelogEntry;
  @Param @Require cardWidth: number;
  @Event onOpenDownload: (url: string) => void = () => {};

  build(): void {
    Column({ space: 12 }) {
      Row() {
        Text(this.entry.channel === ChangelogChannel.STABLE ? '正式版' : '开发版')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.brand'))

        Blank()

        Text(this.entry.channel === ChangelogChannel.STABLE ? `构建日期 ${this.entry.date}` : this.entry.date)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')

      Text(this.entry.version)
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(14)

      Text(this.entry.summary)
        .width('100%')
        .fontSize(16)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(3)

      Text(this.entry.baseline)
        .width('100%')
        .fontSize(13)
        .fontColor($r('sys.color.font_tertiary'))

      if (APP_CHANNEL === 'stable' && this.entry.downloadUrl.length > 0) {
        Column({ space: 8 }) {
          Text('开发版更新更频繁，适合尝鲜用户')
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))

          Button() {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.arrow_down'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_on_primary')])

              Text('获取开发版')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_on_primary'))
            }
          }
          .height(40)
          .padding({ left: 20, right: 20 })
          .type(ButtonType.Capsule)
          .backgroundColor($r('sys.color.brand'))
          .onClick(() => {
            this.onOpenDownload(this.entry.downloadUrl);
          })
        }
        .alignItems(HorizontalAlign.Start)
      }

      if (this.entry.categories.length > 0) {
        Column({ space: 12 }) {
          ForEach(this.entry.categories, (group: ChangelogCategoryGroup) => {
            ChangelogCategorySection({ group: group })
          }, (group: ChangelogCategoryGroup): string => `${group.key}-${group.version}-${group.items.length}`)
        }
        .width('100%')
      } else {
        Column() {
          ForEach(this.entry.changes, (change: string, idx: number) => {
            ChangelogChangeRow({ change: change })
          }, (change: string, idx: number): string => `${idx}-${change}`)
        }
        .width('100%')
      }
    }
    .width(this.cardWidth)
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(20)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}

@HMRouter({ pageUrl: 'ChangelogPage' })
@ComponentV2
export struct ChangelogPage {
  private scroller: Scroller = new Scroller();

  @Computed
  get viewportWidth(): number {
    return WindowUtil.width > 0 ? WindowUtil.width : 360;
  }

  @Computed
  get contentWidth(): number {
    const horizontalInset: number = this.viewportWidth >= 720 ? 64 : 24;
    return Math.min(MAX_CONTENT_WIDTH, Math.max(296, this.viewportWidth - horizontalInset));
  }

  @Computed
  get visibleEntries(): ChangelogEntry[] {
    return resolveChangelogEntries(APP_CHANNEL, APP_VERSION, APP_RELEASE_DATE);
  }

  private openDownload(url: string): void {
    if (url.length === 0 || !AppManager.content.context) {
      sendToast('打开开发版链接失败', $r('sys.symbol.exclamationmark_circle'), 1);
      return;
    }
    (AppManager.content.context as common.UIAbilityContext).openLink(url).catch(() => {
      sendToast('打开开发版链接失败', $r('sys.symbol.exclamationmark_circle'), 1);
    });
  }

  build(): void {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank()
            .width('100%')
            .height(56)

          Column({ space: 24 }) {
            ForEach(this.visibleEntries, (entry: ChangelogEntry) => {
              ChangelogEntryCard({
                entry: entry,
                cardWidth: this.contentWidth,
                onOpenDownload: (url: string): void => {
                  this.openDownload(url);
                }
              })
            }, (entry: ChangelogEntry): string => `${entry.channel}-${entry.version}-${entry.date}`)
          }
          .width('100%')
          .padding({ top: 16, bottom: 32 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor($r('sys.color.background_secondary'))
    }
    .bindToScrollable([this.scroller])
    .titleBar({
      style: pageTitleBarStyle(),
      content: {
        title: {
          mainTitle: '更新日志',
          subTitle: APP_CHANNEL === 'stable' ? '正式版本变化与修复记录' : '开发版本变化与修复记录'
        }
      }
    })
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .hideTitleBar(false)
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
