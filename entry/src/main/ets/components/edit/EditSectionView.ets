import { EditRenderNode, EditSectionRenderPlan } from '../../config/render/EditRenderNode'
import { RecursiveJsonEditor } from './RecursiveJsonEditor'
import { BoolField } from './field/BoolField'
import { getFieldI18Name } from './FieldLabel'

interface FlagRenderRow {
  key: string
  nodes: EditRenderNode[]
}

class EditRenderNodeDataSource implements IDataSource {
  private nodes: EditRenderNode[] = []
  private listeners: DataChangeListener[] = []

  setNodes(nodes: EditRenderNode[]): void {
    this.nodes = nodes
    this.notifyDataReload()
  }

  clear(): void {
    this.nodes = []
    this.notifyDataReload()
  }

  dispose(): void {
    this.nodes = []
    this.listeners = []
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
  private rows: FlagRenderRow[] = []
  private listeners: DataChangeListener[] = []

  setRows(rows: FlagRenderRow[]): void {
    this.rows = rows
    this.notifyDataReload()
  }

  clear(): void {
    this.rows = []
    this.notifyDataReload()
  }

  dispose(): void {
    this.rows = []
    this.listeners = []
  }

  totalCount(): number {
    return this.rows.length
  }

  getData(index: number): FlagRenderRow {
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
  @Param ready: boolean = true
  @Provider() field_width: number = 360
  private dataSource: EditRenderNodeDataSource = new EditRenderNodeDataSource()
  private flagRowDataSource: FlagRowDataSource = new FlagRowDataSource()
  private lastReady: boolean | undefined = undefined
  private lastSectionKey: string = ''

  aboutToAppear(): void {
    this.updateDataSource()
  }

  aboutToUpdate(): void {
    this.updateDataSource()
  }

  aboutToDisappear(): void {
    this.dataSource.dispose()
    this.flagRowDataSource.dispose()
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
    if (this.lastReady === this.ready && this.lastSectionKey === this.section.key) {
      return
    }
    this.lastReady = this.ready
    this.lastSectionKey = this.section.key
    if (!this.ready) {
      this.dataSource.clear()
      this.flagRowDataSource.clear()
      return
    }
    if (this.useFlagRows()) {
      this.dataSource.clear()
      this.flagRowDataSource.setRows(this.buildFlagRows(this.flagNodes()))
    } else {
      this.dataSource.setNodes(this.section.nodes)
      this.flagRowDataSource.clear()
    }
  }

  private buildFlagRows(nodes: EditRenderNode[]): FlagRenderRow[] {
    const rows: FlagRenderRow[] = []
    for (let index = 0; index < nodes.length; index += 2) {
      const row = nodes.slice(index, index + 2)
      rows.push({ key: row.map((node) => node.renderKey).join('|'), nodes: row })
    }
    return rows
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
        LazyForEach(this.flagRowDataSource, (row: FlagRenderRow) => {
          ListItem() {
            Row({ space: 10 }) {
              ForEach(row.nodes, (node: EditRenderNode) => {
                BoolField({ field: node.name, fieldPath: node.path, text: getFieldI18Name(node.name) })
              }, (node: EditRenderNode) => node.renderKey)
            }
            .width('100%')
            .onAreaChange((a, b) => {
              const width = b.width.valueOf() as number
              if (this.field_width !== width) {
                this.field_width = width
              }
            })
          }
          .width('100%')
        }, (row: FlagRenderRow) => row.key)
      } else {
        LazyForEach(this.dataSource, (node: EditRenderNode) => {
          ListItem() {
            RecursiveJsonEditor({ node: node })
              .width('100%')
          }
        }, (node: EditRenderNode) => node.renderKey)
      }
      ListItem()
        .width('100%')
        .height(150)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .cachedCount(1, false)
    .chainAnimation(true)
    .edgeEffect(EdgeEffect.None)
    .padding({ left: 20, right: 20 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  build() {
    if (this.ready) {
      this.listView()
    } else {
      this.loadingView()
    }
  }
}
