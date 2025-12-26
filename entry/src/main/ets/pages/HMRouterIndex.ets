import { HMDefaultGlobalAnimator, HMNavigation } from '@hadss/hmrouter';
import { AttributeUpdater, FrameCallback } from '@kit.ArkUI';
import { EventHelper } from '../util/EventHelper';
import { EnvironmentCallback } from '@kit.AbilityKit';
import { AppManager } from '../AppManager';
import { DragOverlayBuilder } from '../components/util/DragOverlay';
import { NodeNameMap } from './nodes/CompNode';
import { Position } from '../LayoutUtil';
import { DialogHub, DialogMode } from '@hadss/dialoghub';
import { statusBarManager } from '@kit.DeskTopExtensionKit';
import { image } from '@kit.ImageKit';
import { Logger } from '../util/Logger';
import { deviceInfo } from '@kit.BasicServicesKit';
import { deferredLink } from '@kit.AppLinkingKit';
import { url } from '@kit.ArkTS';
import { uncompressStr } from '../CompressUtil';
import { unmappedJson } from '../MappedUtil';

class MyNavModifier extends AttributeUpdater<NavigationAttribute> {
  initializeModifier(instance: NavigationAttribute): void {
    instance.hideNavBar(true);
  }
}

export class MyFrameCallback extends FrameCallback {
  callback: () => void

  constructor(callback: () => void) {
    super();
    this.callback = callback
  }

  onFrame() {
    this.callback()
  }
}

@Entry
@ComponentV2
export struct HMRouterIndex {
  modifier: MyNavModifier = new MyNavModifier();
  @Local dragOverlay: boolean = false
  compPos: Position | undefined
  dragType: string | undefined
  onlyDrag: boolean = false

  async aboutToAppear(): Promise<void> {
    DialogHub.init(this.getUIContext(), DialogMode.CUSTOM_DIALOG);
    AppManager.init(this.getUIContext())
    EventHelper.emitterListener("drag_overlay_on", (data) => {
      this.dragType = data.data!.type
      this.compPos = data.data!.pos
      this.dragOverlay = true
      AppManager.layout.getCompSize(this.dragType!).isOnOverlay = true
    })
    EventHelper.emitterListener("drag_overlay_only_drag", (data) => {
      this.dragType = data.data!.type
      this.compPos = data.data!.pos
      this.onlyDrag = true
      this.dragOverlay = true
      AppManager.layout.getCompSize(this.dragType!).isOnOverlay = true
    })
    EventHelper.emitterListener("drag_overlay_off", () => {
      AppManager.layout.getCompSize(this.dragType!).isOnOverlay = false
      this.dragType = undefined
      this.dragOverlay = false
    })
    let environmentCallback: EnvironmentCallback = {
      onMemoryLevel: (): void => {
      },
      onConfigurationUpdated: (): void => {
        this.getUIContext()?.postFrameCallback(new MyFrameCallback(() => {
          Array.from(NodeNameMap.values()).forEach((value) => {
            value.updateConfiguration();
          })
        }));
      }
    };
    this.getUIContext().getHostContext()?.getApplicationContext().on('environment', environmentCallback);
    if (canIUse("SystemCapability.PCService.StatusBarManager")) {
      try {
        const blackFileData =
          this.getUIContext().getHostContext()!.resourceManager.getRawFileContentSync('statusBar.svg');
        const blackBuffer = blackFileData.buffer;
        const blackImageSource = image.createImageSource(blackBuffer);
        let blackPixelMap = await blackImageSource.createPixelMap();
        let item: statusBarManager.StatusBarItem = {
          icons: {
            white: blackPixelMap,
            black: blackPixelMap
          },
          quickOperation: {
            abilityName: "StatusBarViewAbility",
            title: "EasyTier v" +
              (deviceInfo.productModel !== "emulator" ? AppManager.easytier.version().split("-")[0] : "N/A"),
            height: 300
          },
          statusBarGroupMenu: [
            [
              {
                title: "打开主界面",
                menuAction: {
                  abilityName: "EntryAbility"
                }
              }
            ]
          ]
        };
        statusBarManager.addToStatusBar(this.getUIContext().getHostContext(), item);
      } catch (error) {
        Logger.error(`addToStatusBar failed. error code: ${error.code}, error message: ${error.message}`, "HMRouterIndex");
      }
    }
    if (canIUse("SystemCapability.BundleManager.AppLinking.DeferredLink")) {
      EventHelper.commonListener("usual.event.PRIVACY_STATE_CHANGED", () => {
        deferredLink.popDeferredLink().then(async (link: string) => {
          if (link) {
            try {
              let urlObject = url.URL.parseURL(link);
              let cfg = urlObject.params.get('cfg');
              let config = unmappedJson(await uncompressStr(cfg))
              let uuid = AppManager.data.safeUUID()
              if (!config.instance_id) {
                config.instance_id = uuid
              }
              AppManager.data.readConfig(config.instance_id!, config.instance_id!, config)
            } catch (_) {}
          }
        })
      }, undefined)
    }
  }

  build() {
    Column() {
      HMNavigation({
        navigationId: 'MainNavigation', homePageUrl: 'HomePage',
        options: {
          dialogAnimator: HMDefaultGlobalAnimator.DIALOG_ANIMATOR,
          modifier: this.modifier
        }
      })
        .height('100%')
        .width('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .bindContentCover($$this.dragOverlay, DragOverlayBuilder(this.dragType, this.onlyDrag, this.compPos), {
      modalTransition: ModalTransition.NONE,
      onWillDisappear: () => {
        this.onlyDrag = false
        if (this.dragType) {
          this.dragType = undefined
          AppManager.layout.getCompSize(this.dragType!).isOnOverlay = false
        }
      }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .height('100%')
    .width('100%')
    .onTouch((event) => {
      if (event.type == TouchType.Down) {
        EventHelper.emitterPublish("resize_off")
        EventHelper.emitterPublish("click_edit")
      }
    })
  }
}