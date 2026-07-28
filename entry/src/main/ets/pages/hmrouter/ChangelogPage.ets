import { HMRouter } from '@hadss/hmrouter';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { WindowUtil } from '../../WindowUtil';
import { CHANGELOG_ENTRIES, ChangelogEntry } from './ChangelogData';
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
        Text(entry.date)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))

        Blank()

        Text(entry.version === '开发版' ? '当前开发记录' : '历史版本')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.brand'))
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
          ForEach(CHANGELOG_ENTRIES, (entry: ChangelogEntry) => {
            this.EntryCard(entry);
          }, (entry: ChangelogEntry): string => `${entry.version}-${entry.date}`)
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
          subTitle: '功能变化与修复记录'
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
