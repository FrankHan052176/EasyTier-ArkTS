import { BuilderNode, FrameNode, NodeController, UIContext } from '@kit.ArkUI';
import { AppManager } from '../../AppManager';
import { Instances } from '../../components/index/Instances';
import { Favorite } from '../../components/index/Favorite';
import { Logs as Logs } from '../../components/index/Logs';
import { QQGroups } from '../../components/index/QQGroups';
import { SharedPeers } from '../../components/index/SharedPeers';
import { lane } from '../../util/Conversion';
import { ResizableComponent } from './ResizableComponent';

class Params {
  comp: string = "this is the type of comp"
}

@Builder
function buildComp(params: Params) {
  ResizableComponent({comp_type: params.comp}) {
    if (params.comp == "Instances") {
      Instances()
    }else if (params.comp === "Favorite") {
      Favorite()
    }else if (params.comp === "Logs") {
      Logs()
    }else if (params.comp === "SharedPeers") {
      SharedPeers()
    }else if (params.comp === "QQ") {
      QQGroups()
    }else {
      Text(params.comp)
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 36 })
    }
  }
}

@Builder
export function CompNodeBuilder(type: string) {
  Column() {
    if (AppManager.layout.getCompSize(type).isOnOverlay) {
      NodeContainer(getCompNode(type))
    }
  }
  .alignItems(HorizontalAlign.Center)
  .justifyContent(FlexAlign.Center)
  .width(lane(AppManager.layout.getCompSize(type).lane_w) + 18)
  .height(lane(AppManager.layout.getCompSize(type).lane_h) + 18)
}

export class CompNode extends NodeController {
  public type: string
  public node: BuilderNode<[Params]> | undefined
  private wrapBuilder: WrappedBuilder<[Params]> = wrapBuilder(buildComp)

  constructor(type: string) {
    super()
    this.type = type
  }

  makeNode(uiContext: UIContext): FrameNode | null {
    if (!this.node) {
      let node = new BuilderNode<[Params]>(uiContext)
      node.build(this.wrapBuilder, { comp: this.type })
      this.node = node
      return node.getFrameNode()
    }else {
      return this.node.getFrameNode()
    }
  }

  updateConfiguration() {
    this.node?.updateConfiguration()
  }
}

export const NodeNameMap: Map<string, CompNode> = new Map()

export function getCompNode(type: string | undefined): CompNode | undefined {
  if (type === undefined) {
    return undefined
  }else if (NodeNameMap.has(type)) {
    return NodeNameMap.get(type)!
  }else {
    let node = new CompNode(type)
    NodeNameMap.set(type, node)
    return node
  }
}