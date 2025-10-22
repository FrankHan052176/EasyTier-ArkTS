import { BuilderNode, FrameNode, NodeController, Position } from '@kit.ArkUI';
import Manager from '../../Manager';
import { laneWidth } from '../../util/Conversion';
import Logger from '../../util/Logger';
import { ResizableComponent } from '../Components';

class Params {
  comp: string = "this is the type of comp"
}

export class CompSize {
  lane_w: number = 1
  lane_h: number = 1
  offset_l: number = 0
  offset_r: number = 0
  offset_u: number = 0
  offset_d: number = 0
}

@Builder
function buildText(params: Params) {
  ResizableComponent({comp_type: params.comp}) {
    Text(params.comp)
      .fontSize(50)
      .fontWeight(FontWeight.Bold)
      .margin({ bottom: 36 })
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
      Manager.comp_sequence.forEach((comp) => {
        let node = new BuilderNode<[Params]>(context);
        node.build(this.wrapBuilder, { comp: comp })
        this.rootNode!.appendChild(node.getFrameNode())
      })
    }
    return this.rootNode;
  }
}

class MyFrameNode extends FrameNode {
  onLayout(position: Position): void {
    for (let i = 0; i < this.getChildrenCount(); i++) {
      let child = this.getChild(i);
      if (child) {
        if (i == 0) {
          child.layout({
            x: vp2px(20),
            y: vp2px(10)
          });
        }else {
          child.layout({
            x: vp2px(20+laneWidth(1)+10),
            y: vp2px(10)
          });
        }
        Logger.debug(""+child.getId())
      }
    }
    this.setLayoutPosition(position);
  }
}

