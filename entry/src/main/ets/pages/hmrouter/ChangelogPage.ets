import { HMRouter } from '@hadss/hmrouter';
import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { AppManager } from '../../AppManager';
import { sendToast } from '../../ToastUtil';
import { WindowUtil } from '../../WindowUtil';
import { APP_CHANNEL, APP_RELEASE_DATE, APP_VERSION } from '../../util/info/BuildTime';
import {
  buildStableChangelogEntries,
  CHANGELOG_ENTRIES,
  ChangelogChannel,
  ChangelogEntry
} from './ChangelogData';
import { pageTitleBarStyle } from './HdsPageStyle';

const MAX_CONTENT_WIDTH: number = 760;

@HMRouter({ pageUrl: 'ChangelogPage' })
@ComponentV2
export struct ChangelogPage {
  private scroller: Scroller = new Scroller();

  private viewportWidth(): number {
    return WindowUtil.width > 0 ? WindowUtil.width : 360;
  }

  private contentWidth(): number {
    let horizontalInset: number = this.viewportWidth() >= 720 ? 64 : 24;
    return Math.min(MAX_CONTENT_WIDTH, Math.max(296, this.viewportWidth() - horizontalInset));
  }

  private visibleEntries(): ChangelogEntry[] {
    if (APP_CHANNEL !== 'stable') {
      return CHANGELOG_ENTRIES;
    }
    return buildStableChangelogEntries(APP_VERSION, APP_RELEASE_DATE);
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

  @Builder
  private ChangeRow(change: string): void {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.checkmark_circle'))
        .fontSize(19)
        .fontColor([$r('sys.color.brand')])

      Text(change)
        .layoutWeight(1)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  private EntryCard(entry: ChangelogEntry): void {
    Column({ space: 12 }) {
      Row() {
        Text(entry.channel === ChangelogChannel.STABLE ? '正式版' : '开发版')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.brand'))

        Blank()

        Text(entry.channel === ChangelogChannel.STABLE ? `构建日期 ${entry.date}` : entry.date)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')

      Text(entry.version)
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(14)

      Text(entry.summary)
        .width('100%')
        .fontSize(16)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(3)

      Text(entry.baseline)
        .width('100%')
        .fontSize(13)
        .fontColor($r('sys.color.font_tertiary'))

      if (APP_CHANNEL === 'stable' && entry.downloadUrl.length > 0) {
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
            this.openDownload(entry.downloadUrl);
          })
        }
        .alignItems(HorizontalAlign.Start)
      }

      Column() {
        ForEach(entry.changes, (change: string) => {
          this.ChangeRow(change);
        }, (change: string): string => change)
      }
      .width('100%')
    }
    .width(this.contentWidth())
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(20)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }

  @Builder
  private Content(): void {
    Scroll(this.scroller) {
      Column() {
        Blank()
          .width('100%')
          .height(56)

        Column({ space: 24 }) {
          ForEach(this.visibleEntries(), (entry: ChangelogEntry) => {
            this.EntryCard(entry);
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

  build(): void {
    HdsNavigation() {
      this.Content();
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
