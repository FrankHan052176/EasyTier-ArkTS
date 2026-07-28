import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { WindowUtil } from '../../WindowUtil';
import { HdsMenuButton } from '../Components';
import { pageTitleBarStyle } from './HdsPageStyle';
import { TUTORIAL_STEPS, TutorialAction, TutorialStep } from './TutorialData';
import { ChangelogPresentationService } from '../../services/changelog/ChangelogPresentationService';

const WIDE_BREAKPOINT: number = 840;
const MAX_CONTENT_WIDTH: number = 1040;
const RAIL_WIDTH: number = 280;
const LAYOUT_GAP: number = 24;

@HMRouter({ pageUrl: 'HelpPage' })
@ComponentV2
export struct HelpPage {
  @Local currentIndex: number = 0;
  private scroller: Scroller = new Scroller();

  private viewportWidth(): number {
    return WindowUtil.width > 0 ? WindowUtil.width : 360;
  }

  private isWideLayout(): boolean {
    return this.viewportWidth() >= WIDE_BREAKPOINT;
  }

  private contentWidth(): number {
    let horizontalInset: number = this.isWideLayout() ? 64 : 24;
    return Math.min(MAX_CONTENT_WIDTH, Math.max(296, this.viewportWidth() - horizontalInset));
  }

  private detailWidth(): number {
    if (!this.isWideLayout()) {
      return this.contentWidth();
    }
    return this.contentWidth() - RAIL_WIDTH - LAYOUT_GAP;
  }

  private currentStep(): TutorialStep {
    return TUTORIAL_STEPS[this.currentIndex];
  }

  private selectStep(index: number): void {
    this.currentIndex = Math.min(Math.max(index, 0), TUTORIAL_STEPS.length - 1);
  }

  private goPrevious(): void {
    if (this.currentIndex > 0) {
      this.currentIndex--;
    }
  }

  private goNext(): void {
    if (this.currentIndex < TUTORIAL_STEPS.length - 1) {
      this.currentIndex++;
      return;
    }
    this.finishTutorial();
  }

  private finishTutorial(): void {
    HMRouterMgr.pop();
  }

  private stepIcon(index: number): Resource {
    if (index === 0) {
      return $r('sys.symbol.plus_square');
    }
    if (index === 1) {
      return $r('sys.symbol.play_circle');
    }
    if (index === 2) {
      return $r('sys.symbol.superdevice');
    }
    return $r('sys.symbol.gearshape');
  }

  private actionIcon(stepIndex: number, actionIndex: number): Resource {
    if (stepIndex === 0) {
      if (actionIndex === 0) {
        return $r('sys.symbol.plus');
      }
      if (actionIndex === 1) {
        return $r('sys.symbol.share');
      }
      return $r('sys.symbol.file_preview');
    }
    if (stepIndex === 1) {
      if (actionIndex === 0) {
        return $r('sys.symbol.play_circle');
      }
      if (actionIndex === 1) {
        return $r('sys.symbol.list_bullet_square');
      }
      return $r('sys.symbol.waveform');
    }
    if (stepIndex === 2) {
      if (actionIndex === 0) {
        return $r('sys.symbol.superdevice');
      }
      if (actionIndex === 1) {
        return $r('sys.symbol.checkmark_shield');
      }
      return $r('sys.symbol.disconnect');
    }
    if (actionIndex === 0) {
      return $r('sys.symbol.doc_plaintext_and_checkmark');
    }
    if (actionIndex === 1) {
      return $r('sys.symbol.network_acceleration');
    }
    return $r('sys.symbol.cloud');
  }

  private compactStepTitle(index: number): string {
    if (index === 0) {
      return '接入';
    }
    if (index === 1) {
      return '运行';
    }
    if (index === 2) {
      return '控制';
    }
    return '工具';
  }

  @Builder
  private StepRailItem(step: TutorialStep, index: number): void {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 12 }) {
        if (index === this.currentIndex) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(22)
            .fontColor([$r('sys.color.brand')])
        } else {
          Text(`${index + 1}`)
            .width(22)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_secondary'))
            .textAlign(TextAlign.Center)
        }

        Text(step.shortTitle)
          .layoutWeight(1)
          .fontSize(16)
          .fontWeight(index === this.currentIndex ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(index === this.currentIndex ? $r('sys.color.brand') : $r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 14, right: 14 })
    }
    .width('100%')
    .height(56)
    .padding(0)
    .backgroundColor(index === this.currentIndex ?
      $r('app.color.selected_background') : Color.Transparent)
    .borderRadius(14)
    .accessibilityText(step.title)
    .accessibilityDescription(index === this.currentIndex ? '当前步骤' : step.subtitle)
    .onClick((): void => {
      this.selectStep(index);
    })
  }

  @Builder
  private StepRail(): void {
    Column({ space: 8 }) {
      Text('快速上手')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))

      Text('按任务选择步骤')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .margin({ bottom: 8 })

      ForEach(TUTORIAL_STEPS, (step: TutorialStep, index: number) => {
        this.StepRailItem(step, index);
      }, (step: TutorialStep): string => step.id)
    }
    .width(RAIL_WIDTH)
    .padding(20)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(20)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }

  @Builder
  private ActionRow(action: TutorialAction, actionIndex: number): void {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.actionIcon(this.currentIndex, actionIndex))
          .fontSize(22)
          .fontColor([$r('sys.color.brand')])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .borderRadius(12)

      Column({ space: 3 }) {
        Text(action.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))

        Text(action.description)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  private DetailCard(): void {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        SymbolGlyph(this.stepIcon(this.currentIndex))
          .fontSize(26)
          .fontColor([$r('sys.color.brand')])

        Text(`第 ${this.currentIndex + 1} 步`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.brand'))

        Blank()

        Text(`${this.currentIndex + 1}/${TUTORIAL_STEPS.length}`)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')

      Column({ space: 5 }) {
        Text(this.currentStep().title)
          .width('100%')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(2)

        Text(this.currentStep().subtitle)
          .width('100%')
          .fontSize(16)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Text(this.currentStep().summary)
        .width('100%')
        .padding(16)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(14)
        .maxLines(3)

      Column() {
        ForEach(this.currentStep().actions, (action: TutorialAction, index: number) => {
          this.ActionRow(action, index);
        }, (action: TutorialAction): string => action.title)
      }
      .width('100%')
    }
    .width(this.detailWidth())
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(20)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }

  @Builder
  private NavigationButtons(): void {
    Row({ space: 12 }) {
      Button('上一步')
        .type(ButtonType.Capsule)
        .layoutWeight(1)
        .height(48)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.comp_background_primary'))
        .enabled(this.currentIndex > 0)
        .opacity(this.currentIndex > 0 ? 1 : 0.45)
        .onClick((): void => {
          this.goPrevious();
        })

      Button(this.currentIndex === TUTORIAL_STEPS.length - 1 ? '开始使用' : '下一步')
        .type(ButtonType.Capsule)
        .layoutWeight(1)
        .height(48)
        .fontSize(16)
        .fontColor(Color.White)
        .backgroundColor($r('sys.color.brand'))
        .onClick((): void => {
          this.goNext();
        })
    }
    .width(this.detailWidth())
  }

  @Builder
  private StepTabs(): void {
    Tabs({ barPosition: BarPosition.Start, index: this.currentIndex }) {
      ForEach(TUTORIAL_STEPS, (_step: TutorialStep, index: number) => {
        TabContent() {
          Row()
        }
        .tabBar(this.compactStepTitle(index))
      }, (step: TutorialStep): string => step.id)
    }
    .width(this.contentWidth())
    .height(52)
    .barMode(BarMode.Fixed)
    .animationDuration(180)
    .onChange((index: number): void => {
      this.selectStep(index);
    })
  }

  @Builder
  private NarrowContent(): void {
    Column({ space: 16 }) {
      this.StepTabs();
      this.DetailCard();
      this.NavigationButtons();
    }
    .width(this.contentWidth())
  }

  @Builder
  private WideContent(): void {
    Row({ space: LAYOUT_GAP }) {
      this.StepRail();

      Column({ space: 16 }) {
        this.DetailCard();
        this.NavigationButtons();
      }
      .width(this.detailWidth())
    }
    .width(this.contentWidth())
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private Content(): void {
    Scroll(this.scroller) {
      Column() {
        if (this.isWideLayout()) {
          this.WideContent();
        } else {
          this.NarrowContent();
        }
      }
      .width('100%')
      .padding({ top: 16, bottom: 32 })
      .alignItems(HorizontalAlign.Center)
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
          mainTitle: '快速上手',
          subTitle: '四步完成接入与日常管理'
        },
        menu: {
          value: [
            HdsMenuButton('更新日志', $r('sys.symbol.list_bullet_square'), (): void => {
              ChangelogPresentationService.consumeCurrentVersion();
              HMRouterMgr.push({ pageUrl: 'ChangelogPage' });
            }),
            HdsMenuButton('跳过教程', $r('sys.symbol.xmark'), (): void => {
              this.finishTutorial();
            })
          ]
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
