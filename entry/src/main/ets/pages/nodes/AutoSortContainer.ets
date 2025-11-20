import { BuilderNode, FrameNode, NodeController, Position } from '@kit.ArkUI';
import { Instances } from '../../components/index/Instances';
import { Svp2px } from '../../ContextUtil';
import { LayoutUtil } from '../../LayoutUtil';
import { lane } from '../../util/Conversion';
import { Logger } from '../../util/Logger';
import { ResizableComponent } from './ResizableComponent';

class Params {
  comp: string = "this is the type of comp"
}

@Builder
function buildText(params: Params) {
  ResizableComponent({comp_type: params.comp}) {
    if (params.comp == "Instances") {
      Instances()
    }else {
      Text(params.comp)
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 36 })
    }
  }
}

export class AutoSortContainer extends NodeController {
  public rootNode: MyFrameNode | null = null;
  private Nodes: BuilderNode<[Params]>[] = [];
  private wrapBuilder: WrappedBuilder<[Params]> = wrapBuilder(buildText);

  makeNode(context: UIContext): FrameNode | null {
    if (this.rootNode == null) {
      this.rootNode = new MyFrameNode(context);
      this.rootNode.commonAttribute
        .width("100%")
        .padding({top: 10, left: 20, right: 20, bottom: 50})
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    if (this.Nodes.length == 0) {
      LayoutUtil.comp_sequence.forEach((comp) => {
        let node = new BuilderNode<[Params]>(context);
        node.build(this.wrapBuilder, { comp: comp })
        this.rootNode!.appendChild(node.getFrameNode())
      })
    }
    return this.rootNode;
  }
}

class MyFrameNode extends FrameNode {

  constructor(context: UIContext) {
    super(context);
  }

  onLayout(position: Position): void {
    Logger.debug("onLayout")
    for (let i = 0; i < this.getChildrenCount(); i++) {
      const child = this.getChild(i);
      if (!child) continue;
      const compType = LayoutUtil.comp_sequence[i];
      const compSize = LayoutUtil.getCompSize(compType);
      const gridSize = lane(1) + 10;
      const grid_x = compSize.grid_x;
      const grid_y = compSize.grid_y;
      const pixelX = Svp2px(20 + grid_x * gridSize);
      const pixelY = Svp2px(10 + grid_y * gridSize);
      child.layout({
        x: pixelX,
        y: pixelY
      });
    }
    this.setLayoutPosition(position);
  }
}