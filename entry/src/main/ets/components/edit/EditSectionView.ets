import { EditRenderNode, EditSectionRenderPlan } from '../../config/render/EditRenderNode'
import { RecursiveJsonEditor } from './RecursiveJsonEditor'
import { BoolField, boolFieldHeight } from './field/BoolField'
import { getFieldI18Name } from './FieldLabel'
import { perfLog, PerfSpan } from '../../services/runtime/PerfTrace'
import { FrameCallback } from '@kit.ArkUI'

interface FlagRenderRow {
  key: string
  nodes: EditRenderNode[]
}

/** List 链式弹簧动画开关。A/B 已验证不是掉帧主因，恢复为开启 */
const EDIT_LIST_CHAIN_ANIMATION = true

/** List 左右内边距，与下方 .padding 保持一致 */
const LIST_HORIZONTAL_PADDING = 20

/** 普通 Schema 每帧放出的行数 */
const DEFAULT_ROWS_PER_FRAME = 3

/**
 * Flag 卡片包含完整的文本、Symbol 和交互状态，三栏首屏时每帧只创建一行
 * （两个 BoolField），避免和另外两栏的构建工作叠在同一帧。
 */
const FLAG_ROWS_PER_FRAME = 1

/** postFrameCallback 载体 */
class RevealFrameCallback extends FrameCallback {
  private readonly handler: () => void

  constructor(handler: () => void) {
    super()
    this.handler = handler
  }

  onFrame(_frameTimeNanos: number): void {
    this.handler()
  }
}

/** 字段名 → 资源对象缓存，避免每次构建都做字符串拼接和 Resource 分配 */
const fieldLabelCache: Map<string, ResourceStr> = new Map()

function cachedFieldLabel(field: string): ResourceStr {
  const hit = fieldLabelCache.get(field)
  if (hit !== undefined) {
    return hit
  }
  const label = getFieldI18Name(field)
  fieldLabelCache.set(field, label)
  return label
}

class EditRenderNodeDataSource implements IDataSource {
  private nodes: EditRenderNode[] = []
  /** 已暴露给 LazyForEach 的条数；totalCount 只报这个数 */
  private revealed: number = 0
  private listeners: DataChangeListener[] = []

  setNodes(nodes: EditRenderNode[]): void {
    this.nodes = nodes
    this.revealed = 0
    this.notifyDataReload()
  }

  /** 再放出一批，返回是否仍有剩余 */
  revealMore(count: number): boolean {
    const target = Math.min(this.nodes.length, this.revealed + count)
    while (this.revealed < target) {
      const index = this.revealed
      this.revealed++
      // 必须用 onDataAdd 增量通知：onDataReloaded 会让整个列表重建，适得其反
      this.listeners.forEach((listener) => {
        listener.onDataAdd(index)
      })
    }
    return this.revealed < this.nodes.length
  }

  hasPending(): boolean {
    return this.revealed < this.nodes.length
  }

  clear(): void {
    this.nodes = []
    this.revealed = 0
    this.notifyDataReload()
  }

  dispose(): void {
    this.nodes = []
    this.revealed = 0
    this.listeners = []
  }

  totalCount(): number {
    return this.revealed
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
  /** 已暴露给 LazyForEach 的条数；totalCount 只报这个数 */
  private revealed: number = 0
  private listeners: DataChangeListener[] = []

  setRows(rows: FlagRenderRow[]): void {
    this.rows = rows
    this.revealed = 0
    this.notifyDataReload()
  }

  /** 再放出一批，返回是否仍有剩余 */
  revealMore(count: number): boolean {
    const target = Math.min(this.rows.length, this.revealed + count)
    while (this.revealed < target) {
      const index = this.revealed
      this.revealed++
      this.listeners.forEach((listener) => {
        listener.onDataAdd(index)
      })
    }
    return this.revealed < this.rows.length
  }

  hasPending(): boolean {
    return this.revealed < this.rows.length
  }

  clear(): void {
    this.rows = []
    this.revealed = 0
    this.notifyDataReload()
  }

  dispose(): void {
    this.rows = []
    this.revealed = 0
    this.listeners = []
  }

  totalCount(): number {
    return this.revealed
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
  @Local flagRevealPending: boolean = false
  private dataSource: EditRenderNodeDataSource = new EditRenderNodeDataSource()
  private flagRowDataSource: FlagRowDataSource = new FlagRowDataSource()
  private lastReady: boolean | undefined = undefined
  private lastSectionKey: string = ''
  private buildStartedAt: number = 0
  private revealScheduled: boolean = false
  private revealTimer: number = -1
  private revealGeneration: number = 0
  private revealActive: boolean = false
  private usingFlagRows: boolean = false

  aboutToAppear(): void {
    this.revealActive = true
    this.buildStartedAt = Date.now()
    const span = new PerfSpan('section.updateDataSource')
    this.updateDataSource()
    span.end(`key=${this.section.key} nodes=${this.section.nodes.length} ready=${this.ready}`)
  }

  /** 组件首次构建完成：aboutToAppear→onDidBuild 即该分组的构建+布局耗时 */
  onDidBuild(): void {
    if (this.buildStartedAt === 0) {
      return
    }
    perfLog(`section.didBuild key=${this.section.key} cost=${Date.now() - this.buildStartedAt}ms`)
    this.buildStartedAt = 0
  }

  aboutToUpdate(): void {
    const span = new PerfSpan('section.aboutToUpdate')
    this.updateDataSource()
    span.end(`key=${this.section.key} ready=${this.ready}`)
  }

  aboutToDisappear(): void {
    this.revealActive = false
    this.cancelReveal()
    this.dataSource.dispose()
    this.flagRowDataSource.dispose()
  }

  /** 复用回收时也要停掉逐帧放行，否则回收中的实例还在刷新数据源 */
  aboutToRecycle(): void {
    this.revealActive = false
    this.cancelReveal()
  }

  aboutToReuse(): void {
    this.revealActive = true
    this.lastReady = undefined
    this.lastSectionKey = ''
    this.updateDataSource()
  }

  private cancelReveal(): void {
    this.revealGeneration++
    if (this.revealTimer >= 0) {
      clearTimeout(this.revealTimer)
      this.revealTimer = -1
    }
    this.revealScheduled = false
  }

  /**
   * 一次性灌满数据源会让 LazyForEach 在一个 measure pass 里构建整屏 item，
   * 实测单帧 40ms 以上；Flag 进一步收紧为每帧一行。
   */
  private scheduleReveal(): void {
    if (this.revealScheduled) {
      return
    }
    const pending = this.usingFlagRows ? this.flagRowDataSource.hasPending() : this.dataSource.hasPending()
    if (!pending) {
      return
    }
    this.revealScheduled = true
    const generation = this.revealGeneration
    const step = () => {
      if (!this.revealActive || generation !== this.revealGeneration) {
        return
      }
      this.revealScheduled = false
      this.revealTimer = -1
      if (this.usingFlagRows) {
        this.flagRevealPending = this.flagRowDataSource.revealMore(FLAG_ROWS_PER_FRAME)
      } else {
        this.dataSource.revealMore(DEFAULT_ROWS_PER_FRAME)
      }
      this.scheduleReveal()
    }
    try {
      this.getUIContext().postFrameCallback(new RevealFrameCallback(step))
    } catch (_) {
      this.revealTimer = setTimeout(step, 16)
    }
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

  private updateDataSource(): void {
    if (this.lastReady === this.ready && this.lastSectionKey === this.section.key) {
      return
    }
    this.cancelReveal()
    this.lastReady = this.ready
    this.lastSectionKey = this.section.key
    if (!this.ready) {
      this.usingFlagRows = false
      this.flagRevealPending = false
      this.dataSource.clear()
      this.flagRowDataSource.clear()
      return
    }
    const flagNodes = this.flagNodes()
    this.usingFlagRows = flagNodes.length > 0
    if (this.usingFlagRows) {
      this.dataSource.clear()
      this.flagRowDataSource.setRows(this.buildFlagRows(flagNodes))
      this.flagRevealPending = this.flagRowDataSource.hasPending()
    } else {
      this.flagRevealPending = false
      this.dataSource.setNodes(this.section.nodes)
      this.flagRowDataSource.clear()
    }
    // 数据只是灌进来了，实际按帧逐批放给 LazyForEach
    this.scheduleReveal()
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
      if (this.usingFlagRows) {
        LazyForEach(this.flagRowDataSource, (row: FlagRenderRow) => {
          ListItem() {
            Row({ space: 10 }) {
              ForEach(row.nodes, (node: EditRenderNode) => {
                BoolField({ field: node.name, fieldPath: node.path, text: cachedFieldLabel(node.name) })
              }, (node: EditRenderNode) => node.renderKey)
            }
            .width('100%')
          }
          .width('100%')
          // 定高：BoolField 本身就是固定高度，把高度显式告诉 ListItem，
          // List 测量这一行时不必再钻进子树按内容算高。
          .height(boolFieldHeight())
        }, (row: FlagRenderRow) => row.key)
        if (this.flagRevealPending) {
          ListItem() {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(18)
                .height(18)
              Text($r('app.string.editing_flags_loading'))
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
            }
            .width('100%')
            .height(44)
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .height(44)
        }
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
    // 宽度只在 List 这一个节点上测一次，别逐行测。
    // 原来每个 flag 行都挂回调写 @Provider field_width，而 BoolField 的
    // cellWidth/textWidth/symbolSize 三个 @Computed 都依赖它——测量过程中
    // 写入会让 22 个 BoolField 的 Computed 集体失效并再标脏一轮，
    // 形成“测量→写状态→再测量”的反馈环（trace 里的 updateDirtyComputedProps 22 @Computed）。
    .onSizeChange((_o: SizeOptions, n: SizeOptions) => {
      const width = (n.width as number) - LIST_HORIZONTAL_PADDING * 2
      if (width > 0 && this.field_width !== width) {
        this.field_width = width
      }
    })
    .cachedCount(1, false)
    // A/B 排查：chainAnimation 每个 item 都要算弹簧动画，滚动期间是实打实的开销
    .chainAnimation(EDIT_LIST_CHAIN_ANIMATION)
    .edgeEffect(EdgeEffect.None)
    .padding({ left: LIST_HORIZONTAL_PADDING, right: LIST_HORIZONTAL_PADDING })
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
