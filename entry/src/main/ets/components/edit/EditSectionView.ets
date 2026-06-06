import { EditRenderNode, EditSectionRenderPlan } from '../../config/render/EditRenderNode'
import { RecursiveJsonEditor } from './RecursiveJsonEditor'
import { BoolField } from './field/BoolField'
import { getFieldI18Name } from './FieldEdit'

class EditRenderNodeDataSource implements IDataSource {
  private nodes: EditRenderNode[] = []
  private listeners: DataChangeListener[] = []

  setNodes(nodes: EditRenderNode[]): void {
    this.nodes = nodes
    this.notifyDataReload()
  }

  totalCount(): number {
    return this.nodes.length
  }

  getData(index: number): EditRenderNode {
    return this.nodes[index]
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

class FlagRowDataSource implements IDataSource {
  private rows: EditRenderNode[][] = []
  private listeners: DataChangeListener[] = []

  setNodes(nodes: EditRenderNode[]): void {
    const rows: EditRenderNode[][] = []
    for (let index = 0; index < nodes.length; index += 2) {
      rows.push(nodes.slice(index, index + 2))
    }
    this.rows = rows
    this.notifyDataReload()
  }

  totalCount(): number {
    return this.rows.length
  }

  getData(index: number): EditRenderNode[] {
    return this.rows[index]
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
export struct EditSectionView {
  @Param @Require section: EditSectionRenderPlan
  @Provider() field_width: number = 360
  private dataSource: EditRenderNodeDataSource = new EditRenderNodeDataSource()
  private flagRowDataSource: FlagRowDataSource = new FlagRowDataSource()

  aboutToAppear(): void {
    this.updateDataSource()
  }

  private flagNodes(): EditRenderNode[] {
    if (this.section.key !== 'flags' || this.section.nodes.length !== 1) {
      return []
    }
    const root = this.section.nodes[0]
    if (root.kind !== 'group' || root.children.length === 0) {
      return []
    }
    if (!root.children.every((node) => node.kind === 'boolean')) {
      return []
    }
    return root.children
  }

  private useFlagRows(): boolean {
    return this.flagNodes().length > 0
  }

  private updateDataSource(): void {
    if (this.useFlagRows()) {
      this.dataSource.setNodes([])
      this.flagRowDataSource.setNodes(this.flagNodes())
    } else {
      this.dataSource.setNodes(this.section.nodes)
      this.flagRowDataSource.setNodes([])
    }
  }

  @Builder
  skeletonLine(widthValue: string, heightValue: number, radiusValue: number) {
    Row()
      .width(widthValue)
      .height(heightValue)
      .borderRadius(radiusValue)
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .opacity(0.56)
  }

  @Builder
  skeletonCard(index: number) {
    Column({ space: 10 }) {
      Row() {
        this.skeletonLine(index % 2 === 0 ? '42%' : '58%', 10, 5)
        Blank()
        this.skeletonLine('16%', 10, 5)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      this.skeletonLine('100%', 34, 12)
      Row({ space: 8 }) {
        this.skeletonLine('28%', 8, 4)
        this.skeletonLine('20%', 8, 4)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(18)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  loadingView() {
    Column({ space: 14 }) {
      Row()
        .width('100%')
        .height(56)
      ForEach([0, 1, 2], (index: number) => {
        this.skeletonCard(index)
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  listView() {
    List({ space: this.section.key === 'flags' ? 10 : 20 }) {
      ListItem()
        .width('100%')
        .height(56)
      if (this.useFlagRows()) {
        LazyForEach(this.flagRowDataSource, (row: EditRenderNode[]) => {
          ListItem() {
            Row({ space: 10 }) {
              ForEach(row, (node: EditRenderNode) => {
                BoolField({ field: node.name, fieldPath: node.path, text: getFieldI18Name(node.name) })
              }, (node: EditRenderNode) => node.path.join('.') + node.kind)
            }
            .width('100%')
            .onAreaChange((a, b) => {
              this.field_width = b.width.valueOf() as number
            })
          }
          .width('100%')
        }, (row: EditRenderNode[]) => row.map((node) => node.path.join('.')).join('|'))
      } else {
        LazyForEach(this.dataSource, (node: EditRenderNode) => {
          ListItem() {
            RecursiveJsonEditor({ node: node })
              .width('100%')
          }
        }, (node: EditRenderNode) => node.path.join('.') + node.kind)
      }
      ListItem()
        .width('100%')
        .height(150)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .cachedCount(4)
    .chainAnimation(true)
    .edgeEffect(EdgeEffect.None)
    .padding({ left: 20, right: 20 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  build() {
    this.listView()
  }
}
