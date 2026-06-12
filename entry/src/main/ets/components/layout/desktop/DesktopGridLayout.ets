import { Want } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { formProvider } from '@kit.FormKit';
import { SymbolGlyphModifier, curves } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { Logger } from '../../../shared/logging/Logger';
import { APP_BUNDLE_NAME, ENTRY_FORM_ABILITY_NAME } from '../../../services/runtime/AbilityRuntimePolicy';

export interface BreakpointConfig {
  breakpoint: number
  columns: number
}

export interface Position {
  x: number
  y: number
}

export interface CompSizeWithPos {
  type: string
  x: number
  y: number
  width: number
  height: number
}

interface GridRect {
  x: number
  y: number
  w: number
  h: number
}

export enum ResizeEdge {
  Left,
  Right,
  Up,
  Down
}

const GRID_GAP: number = 10
const GRID_PADDING: number = 15
const CARD_RADIUS: number = 18
const RESIZE_HANDLE_SIZE: number = 30
const RESIZE_HANDLE_OFFSET: number = RESIZE_HANDLE_SIZE / 2
const RESIZE_BALL_INSET: number = 1
const RESIZE_TOUCH_INSET: number = 20
const RESIZE_TOUCH_BAND_SIZE: number = RESIZE_HANDLE_OFFSET + RESIZE_TOUCH_INSET
const MOVE_DRAG_DISTANCE: number = 8
const MOVE_LAYER_Z_INDEX: number = 80
const RESIZE_CHROME_Z_INDEX: number = 110
const RESIZE_HANDLE_Z_INDEX: number = 120
const DROP_WAVE_MAX_DELAY: number = 500
const DROP_WAVE_MIN_OFFSET: number = 5
const DROP_WAVE_MAX_OFFSET: number = 18
const DROP_WAVE_REBOUND_RATIO: number = 0.14
const DESKTOP_LAYOUT_LOG_TAG: string = 'DesktopGridLayout'

const layoutAnimationParam: AnimateParam = {
  duration: 200,
  curve: Curve.Friction
}

const avoidApproachAnimationParam: AnimateParam = {
  duration: 155,
  curve: curves.cubicBezierCurve(0.16, 0.0, 0.12, 1.0)
}

const avoidSettleAnimationParam: AnimateParam = {
  duration: 90,
  curve: curves.cubicBezierCurve(0.20, 0.0, 0.0, 1.0)
}

function desktopLayoutDebug(message: string) {
  const log = `[DesktopGridLayout] ${message}`
  Logger.debug(log, DESKTOP_LAYOUT_LOG_TAG)
  console.info(log)
}

function resizeEdgeName(edge: ResizeEdge): string {
  if (edge === ResizeEdge.Left) {
    return 'Left'
  }
  if (edge === ResizeEdge.Right) {
    return 'Right'
  }
  if (edge === ResizeEdge.Up) {
    return 'Up'
  }
  return 'Down'
}

@Builder
function contentComp(type: string) {
  Column() {
    Text(type)
      .fontSize(50)
      .fontWeight(FontWeight.Bold)
  }
  .width('100%')
  .height('100%')
  .alignItems(HorizontalAlign.Center)
  .justifyContent(FlexAlign.Center)
}

export function symbolWithSize(symbol: Resource, size: number): SymbolGlyphModifier {
  const modifier = new SymbolGlyphModifier(symbol)
  modifier.fontSize(size)
  modifier.fontColor([$r('sys.color.font_primary')])
  return modifier
}

@ObservedV2
export class CompSize {
  @Trace type: string = ''
  @Trace lane_w: number = 1
  @Trace lane_h: number = 1
  @Trace offset_l: number = 0
  @Trace offset_r: number = 0
  @Trace offset_u: number = 0
  @Trace offset_d: number = 0
  @Trace grid_x: number = 0
  @Trace grid_y: number = 0
  @Trace isResize: boolean = false
  @Trace isResizing: boolean = false
  @Trace resize_guard_id: number = 0
  @Trace isOnOverlay: boolean = false
  @Trace isDragging: boolean = false
  @Trace willHide: boolean = false
  @Trace floatingX: number = 0
  @Trace floatingY: number = 0
  @Trace pan_offset_x: number = 0
  @Trace pan_offset_y: number = 0
  @Trace next_grid_x: number = 0
  @Trace next_grid_y: number = 0
  @Trace find_next_grid: boolean = false
  @Trace waveScale: number = 1
  @Trace waveOffsetX: number = 0
  @Trace waveOffsetY: number = 0
  @Trace wave_anim_id: number = 0
  @Trace visual_offset_x: number = 0
  @Trace visual_offset_y: number = 0
  @Trace visual_anim_id: number = 0

  setPos(x: number, y: number): CompSize {
    this.grid_x = x
    this.grid_y = y
    this.next_grid_x = x
    this.next_grid_y = y
    return this
  }

  withType(type: string): CompSize {
    this.type = type
    return this
  }

  setSize(width: number, height: number): CompSize {
    this.lane_w = width
    this.lane_h = height
    this.resetResizeOffsets()
    return this
  }

  resetResizeOffsets() {
    this.offset_l = 0
    this.offset_r = 0
    this.offset_u = 0
    this.offset_d = 0
  }
}

export class LayoutManager {
  private static layoutMap: Map<string, LayoutUtil> = new Map()

  public static registerLayout(name: string, layout: LayoutUtil) {
    LayoutManager.layoutMap.set(name, layout)
  }

  public static unregisterLayout(name: string) {
    LayoutManager.layoutMap.delete(name)
  }

  public static getLayout(name: string): LayoutUtil | undefined {
    return LayoutManager.layoutMap.get(name)
  }
}

@ObservedV2
export class LayoutUtil {
  @Trace comp_width: number = 0
  @Trace comp_height: number = 0
  @Trace currentColCount: number = 2
  @Trace desktopPosX: number = 0
  @Trace desktopPosY: number = 0
  @Trace desktopWidth: number = 0
  @Trace desktopHeight: number = 0
  @Trace comp_types: string[] = []
  @Trace comp_sequence: string[] = []
  @Trace compSizeMap: Map<string, CompSize> = new Map()
  @Trace MaxHeight: number = 0
  @Trace MaxWidth: number = 0
  @Trace breakpoints: BreakpointConfig[] = []
  @Trace maxCompW: number = 6
  @Trace maxCompH: number = 6
  @Trace draggingType: string = ''
  @Trace revision: number = 0
  public static readonly MIN_COMP_WIDTH = 1
  public static readonly MIN_COMP_HEIGHT = 1
  readonly gap: number = GRID_GAP
  readonly padding: number = GRID_PADDING
  saveSequence: (layout: LayoutUtil) => void = () => {}
  contentBuilder: WrappedBuilder<[string]> = wrapBuilder(contentComp)
  widgetList: string[] = []
  formWantFunc: (comp_type: string) => Want = (comp_type: string) => {
    return {
      bundleName: APP_BUNDLE_NAME,
      abilityName: ENTRY_FORM_ABILITY_NAME,
      parameters: {
        'ohos.extra.param.key.form_dimension': 1,
        'ohos.extra.param.key.form_name': comp_type,
        'ohos.extra.param.key.module_name': 'entry'
      }
    }
  }

  constructor(name: string, sequence: CompSizeWithPos[], types: string[], saveSequence: (layout: LayoutUtil) => void,
    contentBuilder: WrappedBuilder<[string]>, widgetList: string[], formWantFunc: (comp_type: string) => Want,
    breakpoints: BreakpointConfig[] = [
      { breakpoint: 0, columns: 2 },
      { breakpoint: 720, columns: 4 },
      { breakpoint: 1080, columns: 6 }
    ],
    maxCompW: number = 6, maxCompH: number = 6) {
    LayoutManager.registerLayout(name, this)
    types.forEach((type: string) => {
      if (type.length > 0 && !this.comp_types.includes(type)) {
        this.comp_types.push(type)
      }
    })
    this.breakpoints = breakpoints
    this.maxCompW = maxCompW
    this.maxCompH = maxCompH
    this.saveSequence = saveSequence
    this.contentBuilder = contentBuilder
    this.widgetList = widgetList
    this.formWantFunc = formWantFunc
    this.initSequence(sequence)
  }

  @Computed
  get hidden_comps(): string[] {
    return this.comp_types.filter((type: string) => !this.comp_sequence.includes(type))
  }

  private bumpRevision() {
    this.revision = this.revision + 1
  }

  private normalizeSpan(value: number, maxValue: number): number {
    if (Number.isNaN(value)) {
      return 1
    }
    return Math.max(1, Math.min(maxValue, Math.floor(value)))
  }

  updateDisplaySize(width: number, height: number) {
    this.comp_width = width
    this.comp_height = height
    let newColCount = 2
    for (let i = this.breakpoints.length - 1; i >= 0; i--) {
      if (width >= this.breakpoints[i].breakpoint) {
        newColCount = this.breakpoints[i].columns
        break
      }
    }
    newColCount = Math.max(1, newColCount)
    const changed = this.currentColCount !== newColCount
    this.currentColCount = newColCount
    if (changed || this.MaxWidth > newColCount || this.MaxWidth < newColCount - 1) {
      this.updateNewUIType()
    }
    this.bumpRevision()
    desktopLayoutDebug(`updateDisplaySize width=${width} height=${height} cols=${this.currentColCount} changed=${changed} max=${this.MaxWidth}x${this.MaxHeight} revision=${this.revision}`)
  }

  initSequence(sequence: CompSizeWithPos[]) {
    const seen: Set<string> = new Set()
    sequence.forEach((size: CompSizeWithPos) => {
      const width = this.normalizeSpan(size.width, Math.min(this.maxCompW, this.LayoutWidth()))
      const height = this.normalizeSpan(size.height, this.maxCompH)
      if (this.comp_types.indexOf(size.type) >= 0 && !seen.has(size.type) &&
        !Number.isNaN(size.x) && !Number.isNaN(size.y) && width > 0 && height > 0) {
        seen.add(size.type)
        this.comp_sequence.push(size.type)
        let pos: Position = { x: Math.max(0, Math.floor(size.x)), y: Math.max(0, Math.floor(size.y)) }
        if (this.getObstacles(size.type, pos, width, height).length > 0 ||
          this.isOutOfBounds(pos.x, pos.y, width, height)) {
          pos = this.findFreeSpace(width, height)
        }
        if (pos.x < 0 || pos.y < 0) {
          return
        }
        this.compSizeMap.set(size.type,
          new CompSize().setPos(pos.x, pos.y).setSize(width, height).withType(size.type))
        this.MaxHeight = Math.max(this.MaxHeight, pos.y + height)
        this.MaxWidth = Math.max(this.MaxWidth, pos.x + width)
      }
    })
    this.bumpRevision()
  }

  updateNewUIType() {
    const width = this.LayoutWidth()
    if (width <= 0) {
      return
    }
    const tempSequence: string[] = []
    const tempCompSizeMap: Map<string, CompSize> = new Map()
    this.MaxHeight = 0
    this.MaxWidth = 0
    this.comp_sequence.forEach((type: string) => {
      const size = this.getCompSize(type)
      const laneW = Math.min(size.lane_w, width, this.maxCompW)
      const laneH = Math.min(size.lane_h, this.maxCompH)
      const pos = this.findFreeSpace(laneW, laneH, tempSequence, tempCompSizeMap)
      if (pos.x < 0 || pos.y < 0) {
        return
      }
      const nextSize = new CompSize().setPos(pos.x, pos.y).setSize(laneW, laneH).withType(type)
      tempCompSizeMap.set(type, nextSize)
      tempSequence.push(type)
      size.setPos(pos.x, pos.y)
      size.setSize(laneW, laneH)
      size.find_next_grid = false
      this.MaxHeight = Math.max(this.MaxHeight, pos.y + laneH)
      this.MaxWidth = Math.max(this.MaxWidth, pos.x + laneW)
    })
    this.bumpRevision()
  }

  LayoutWidth(): number {
    return Math.max(1, this.currentColCount)
  }

  LayoutHeight(): number {
    return Math.max((this.comp_sequence.length + 1) * Math.max(2, this.maxCompH), this.MaxHeight + this.maxCompH + 2)
  }

  VisibleRows(): number {
    return Math.max(1, this.previewMaxHeight())
  }

  getCompSize(type: string): CompSize {
    if (this.compSizeMap.has(type)) {
      return this.compSizeMap.get(type)!
    }
    const size = new CompSize().withType(type)
    this.compSizeMap.set(type, size)
    return size
  }

  displayGridX(size: CompSize): number {
    return size.find_next_grid ? size.next_grid_x : size.grid_x
  }

  displayGridY(size: CompSize): number {
    return size.find_next_grid ? size.next_grid_y : size.grid_y
  }

  private rectsOverlap(ax: number, ay: number, aw: number, ah: number, bx: number, by: number, bw: number,
    bh: number): boolean {
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by
  }

  isOutOfBounds(x: number, y: number, w: number, h: number): boolean {
    return x < 0 || y < 0 || x + w > this.LayoutWidth() || y + h > this.LayoutHeight()
  }

  getObstacles(compName: string, pos: Position, width: number, height: number): string[] {
    const overlapComps: string[] = []
    for (const comp of this.comp_sequence) {
      if (comp === compName) {
        continue
      }
      const size = this.getCompSize(comp)
      const gridX = this.displayGridX(size)
      const gridY = this.displayGridY(size)
      if (this.rectsOverlap(pos.x, pos.y, width, height, gridX, gridY, size.lane_w, size.lane_h)) {
        overlapComps.push(comp)
      }
    }
    return overlapComps
  }

  canPlaceAt(x: number, y: number, w: number, h: number, overrideSequence: string[] = this.comp_sequence,
    overrideCompSize: Map<string, CompSize> | undefined = undefined): boolean {
    if (this.isOutOfBounds(x, y, w, h)) {
      return false
    }
    for (const comp of overrideSequence) {
      const size = (overrideCompSize && overrideCompSize.has(comp)) ? overrideCompSize.get(comp)! : this.getCompSize(comp)
      const compX = this.displayGridX(size)
      const compY = this.displayGridY(size)
      if (this.rectsOverlap(x, y, w, h, compX, compY, size.lane_w, size.lane_h)) {
        return false
      }
    }
    return true
  }

  findFreeSpace(itemW: number, itemH: number, overrideSequence: string[] = this.comp_sequence,
    overrideCompSize: Map<string, CompSize> | undefined = undefined): Position {
    for (let y = 0; y + itemH <= this.LayoutHeight() + this.maxCompH; y++) {
      for (let x = 0; x + itemW <= this.LayoutWidth(); x++) {
        if (this.canPlaceAt(x, y, itemW, itemH, overrideSequence, overrideCompSize)) {
          return { x, y }
        }
      }
    }
    return { x: -1, y: -1 }
  }

  private canPlaceAgainstMap(x: number, y: number, w: number, h: number, occupied: Map<string, GridRect>): boolean {
    if (this.isOutOfBounds(x, y, w, h)) {
      return false
    }
    for (const rect of occupied.values()) {
      if (this.rectsOverlap(x, y, w, h, rect.x, rect.y, rect.w, rect.h)) {
        return false
      }
    }
    return true
  }

  private findNearestFreeSpace(itemW: number, itemH: number, occupied: Map<string, GridRect>, origin: Position,
    drop: Position): Position {
    let best: Position = { x: -1, y: -1 }
    let bestScore = Number.MAX_VALUE
    const maxY = this.LayoutHeight() + this.maxCompH
    for (let y = 0; y + itemH <= maxY; y++) {
      for (let x = 0; x + itemW <= this.LayoutWidth(); x++) {
        if (!this.canPlaceAgainstMap(x, y, itemW, itemH, occupied)) {
          continue
        }
        const originDx = x - origin.x
        const originDy = y - origin.y
        const dropDx = x - drop.x
        const dropDy = y - drop.y
        const originScore = originDx * originDx + originDy * originDy
        const dropDistance = Math.sqrt(dropDx * dropDx + dropDy * dropDy)
        const waveBias = Math.max(0, 4 - dropDistance) * 0.25
        const score = originScore + waveBias + y * 0.01 + x * 0.001
        if (score < bestScore) {
          bestScore = score
          best = { x, y }
        }
      }
    }
    return best
  }

  findGridPositionByOffset(type: string, offsetX: number, offsetY: number): Position {
    const size = this.getCompSize(type)
    const period = Math.max(1, this.lane(1) + this.gap)
    const rawX = size.grid_x * period + offsetX
    const rawY = size.grid_y * period + offsetY
    const maxX = Math.max(0, this.LayoutWidth() - size.lane_w)
    const maxY = Math.max(0, this.LayoutHeight() - size.lane_h)
    return {
      x: Math.max(0, Math.min(maxX, Math.round(rawX / period))),
      y: Math.max(0, Math.min(maxY, Math.round(rawY / period)))
    }
  }

  beginDrag(type: string): boolean {
    if (!this.comp_sequence.includes(type)) {
      desktopLayoutDebug(`beginDrag ignored missing type=${type}`)
      return false
    }
    this.closeEditingExcept(type)
    const size = this.getCompSize(type)
    desktopLayoutDebug(`beginDrag type=${type} pos=${size.grid_x},${size.grid_y} size=${size.lane_w}x${size.lane_h}`)
    size.isDragging = true
    size.isOnOverlay = true
    size.find_next_grid = true
    size.next_grid_x = size.grid_x
    size.next_grid_y = size.grid_y
    size.pan_offset_x = 0
    size.pan_offset_y = 0
    size.resetResizeOffsets()
    this.draggingType = type
    this.bumpRevision()
    return true
  }

  updateDrag(type: string, offsetX: number, offsetY: number): boolean {
    if (this.draggingType !== type) {
      desktopLayoutDebug(`updateDrag ignored type=${type} draggingType=${this.draggingType}`)
      return false
    }
    const size = this.getCompSize(type)
    size.pan_offset_x = offsetX
    size.pan_offset_y = offsetY
    const target = this.findGridPositionByOffset(type, offsetX, offsetY)
    if (target.x === size.next_grid_x && target.y === size.next_grid_y) {
      return true
    }
    desktopLayoutDebug(`updateDrag type=${type} offset=${offsetX},${offsetY} target=${target.x},${target.y}`)
    return this.previewMove(type, target)
  }

  private animateVisualOffset(size: CompSize, target: Position) {
    const period = Math.max(1, this.lane(1) + this.gap)
    const oldX = this.displayGridX(size) * period + size.visual_offset_x
    const oldY = this.displayGridY(size) * period + size.visual_offset_y
    const nextOffsetX = oldX - target.x * period
    const nextOffsetY = oldY - target.y * period
    size.visual_anim_id = size.visual_anim_id + 1
    const animId = size.visual_anim_id
    if (Math.abs(nextOffsetX) < 0.1 && Math.abs(nextOffsetY) < 0.1) {
      size.visual_offset_x = 0
      size.visual_offset_y = 0
      return
    }
    const distance = Math.sqrt(nextOffsetX * nextOffsetX + nextOffsetY * nextOffsetY)
    const rebound = Math.min(7, distance * 0.045)
    const reboundX = distance > 0 ? -nextOffsetX / distance * rebound : 0
    const reboundY = distance > 0 ? -nextOffsetY / distance * rebound : 0
    size.visual_offset_x = nextOffsetX
    size.visual_offset_y = nextOffsetY
    setTimeout(() => {
      if (size.visual_anim_id !== animId) {
        return
      }
      animateToImmediately({
        duration: avoidApproachAnimationParam.duration,
        curve: avoidApproachAnimationParam.curve,
        onFinish: () => {
          if (size.visual_anim_id !== animId) {
            return
          }
          animateToImmediately(avoidSettleAnimationParam, () => {
            if (size.visual_anim_id !== animId) {
              return
            }
            size.visual_offset_x = 0
            size.visual_offset_y = 0
          })
        }
      }, () => {
        if (size.visual_anim_id !== animId) {
          return
        }
        size.visual_offset_x = reboundX
        size.visual_offset_y = reboundY
      })
    }, 16)
  }

  previewMove(type: string, target: Position): boolean {
    const dragging = this.getCompSize(type)
    if (this.isOutOfBounds(target.x, target.y, dragging.lane_w, dragging.lane_h)) {
      desktopLayoutDebug(`previewMove rejected outOfBounds type=${type} target=${target.x},${target.y} size=${dragging.lane_w}x${dragging.lane_h}`)
      return false
    }
    const occupied: Map<string, GridRect> = new Map()
    const nextMap: Map<string, Position> = new Map()
    occupied.set(type, { x: target.x, y: target.y, w: dragging.lane_w, h: dragging.lane_h })
    for (const comp of this.comp_sequence) {
      if (comp === type) {
        continue
      }
      const size = this.getCompSize(comp)
      const origin: Position = { x: size.grid_x, y: size.grid_y }
      if (this.canPlaceAgainstMap(origin.x, origin.y, size.lane_w, size.lane_h, occupied)) {
        occupied.set(comp, { x: origin.x, y: origin.y, w: size.lane_w, h: size.lane_h })
        nextMap.set(comp, origin)
        continue
      }
      const free = this.findNearestFreeSpace(size.lane_w, size.lane_h, occupied, origin, target)
      if (free.x < 0 || free.y < 0) {
        desktopLayoutDebug(`previewMove rejected noFreeSpace type=${type} obstacle=${comp} target=${target.x},${target.y}`)
        return false
      }
      occupied.set(comp, { x: free.x, y: free.y, w: size.lane_w, h: size.lane_h })
      nextMap.set(comp, free)
    }
    dragging.next_grid_x = target.x
    dragging.next_grid_y = target.y
    dragging.find_next_grid = true
    nextMap.forEach((pos: Position, comp: string) => {
      const size = this.getCompSize(comp)
      this.animateVisualOffset(size, pos)
      size.next_grid_x = pos.x
      size.next_grid_y = pos.y
      size.find_next_grid = pos.x !== size.grid_x || pos.y !== size.grid_y
    })
    this.recomputeBounds(true)
    this.bumpRevision()
    desktopLayoutDebug(`previewMove applied type=${type} next=${target.x},${target.y} revision=${this.revision}`)
    return true
  }

  confirmTempPos() {
    const type = this.draggingType
    if (type.length === 0) {
      desktopLayoutDebug('confirmTempPos ignored empty draggingType')
      return
    }
    const dropSize = this.getCompSize(type)
    const drop: Position = {
      x: dropSize.next_grid_x + dropSize.lane_w / 2,
      y: dropSize.next_grid_y + dropSize.lane_h / 2
    }
    animateToImmediately(layoutAnimationParam, () => {
      this.comp_sequence.forEach((comp: string) => {
        const size = this.getCompSize(comp)
        if (size.find_next_grid) {
          size.grid_x = size.next_grid_x
          size.grid_y = size.next_grid_y
        }
        size.find_next_grid = false
        size.pan_offset_x = 0
        size.pan_offset_y = 0
        size.isResizing = false
        size.resetResizeOffsets()
        size.visual_anim_id = size.visual_anim_id + 1
        size.visual_offset_x = 0
        size.visual_offset_y = 0
        size.wave_anim_id = size.wave_anim_id + 1
        size.waveOffsetX = 0
        size.waveOffsetY = 0
        size.waveScale = 1
        size.isOnOverlay = false
        size.isDragging = false
      })
      dropSize.isResize = true
    })
    this.draggingType = ''
    this.updateSequence()
    desktopLayoutDebug(`confirmTempPos type=${type} drop=${drop.x},${drop.y}`)
    this.triggerDropWave(type, drop)
  }

  cancelTempPos() {
    desktopLayoutDebug(`cancelTempPos draggingType=${this.draggingType}`)
    animateToImmediately(layoutAnimationParam, () => {
      this.comp_sequence.forEach((comp: string) => {
        const size = this.getCompSize(comp)
        size.find_next_grid = false
        size.next_grid_x = size.grid_x
        size.next_grid_y = size.grid_y
        size.pan_offset_x = 0
        size.pan_offset_y = 0
        size.isResizing = false
        size.resetResizeOffsets()
        size.visual_anim_id = size.visual_anim_id + 1
        size.visual_offset_x = 0
        size.visual_offset_y = 0
        size.wave_anim_id = size.wave_anim_id + 1
        size.waveOffsetX = 0
        size.waveOffsetY = 0
        size.waveScale = 1
        size.isDragging = false
        size.isOnOverlay = false
      })
    })
    this.draggingType = ''
    this.recomputeBounds(false)
    this.bumpRevision()
  }

  closeEditingExcept(type: string = '') {
    this.comp_sequence.forEach((comp: string) => {
      if (comp !== type) {
        const size = this.getCompSize(comp)
        if (!size.isDragging) {
          size.isResizing = false
          size.isResize = false
          size.resetResizeOffsets()
        }
      }
    })
    this.bumpRevision()
  }

  updateSequence() {
    this.comp_sequence = this.comp_sequence.sort((a: string, b: string) => {
      const size1 = this.getCompSize(a)
      const size2 = this.getCompSize(b)
      if (size1.grid_y !== size2.grid_y) {
        return size1.grid_y - size2.grid_y
      }
      return size1.grid_x - size2.grid_x
    })
    this.recomputeBounds(false)
    desktopLayoutDebug(`updateSequence sequence=${this.comp_sequence.map((type: string) => {
      const size = this.getCompSize(type)
      return `${type}_${size.grid_x}_${size.grid_y}_${size.lane_w}_${size.lane_h}`
    }).join('|')}`)
    this.saveSequence(this)
    this.bumpRevision()
  }

  private recomputeBounds(usePreview: boolean) {
    this.MaxHeight = 0
    this.MaxWidth = 0
    this.comp_sequence.forEach((type: string) => {
      const size = this.getCompSize(type)
      const x = usePreview ? this.displayGridX(size) : size.grid_x
      const y = usePreview ? this.displayGridY(size) : size.grid_y
      this.MaxHeight = Math.max(this.MaxHeight, y + size.lane_h)
      this.MaxWidth = Math.max(this.MaxWidth, x + size.lane_w)
    })
  }

  private previewMaxHeight(): number {
    let height = 1
    this.comp_sequence.forEach((type: string) => {
      const size = this.getCompSize(type)
      height = Math.max(height, this.displayGridY(size) + size.lane_h)
    })
    return height
  }

  async removeComponent(type: string) {
    const index = this.comp_sequence.indexOf(type)
    if (index < 0) {
      return
    }
    this.comp_sequence.splice(index, 1)
    this.comp_sequence = this.comp_sequence.slice()
    this.compSizeMap.delete(type)
    if (this.draggingType === type) {
      this.draggingType = ''
    }
    this.updateSequence()
  }

  addComponent(type: string) {
    if (!this.comp_types.includes(type) || this.comp_sequence.includes(type)) {
      return
    }
    const compSize = this.getCompSize(type)
    compSize.setSize(1, 1)
    const pos = this.findFreeSpace(1, 1)
    if (pos.x < 0 || pos.y < 0) {
      return
    }
    compSize.setPos(pos.x, pos.y)
    compSize.isResize = true
    this.closeEditingExcept(type)
    this.comp_sequence.push(type)
    this.comp_sequence = this.comp_sequence.slice()
    this.updateSequence()
  }

  resizeComponent(type: string, edge: ResizeEdge, grow: boolean): boolean {
    const size = this.getCompSize(type)
    const edgeName = resizeEdgeName(edge)
    let nextX = size.grid_x
    let nextY = size.grid_y
    let nextW = size.lane_w
    let nextH = size.lane_h
    const widthLimit = Math.min(this.maxCompW, this.LayoutWidth())
    const delta = grow ? 1 : -1
    desktopLayoutDebug(`resize request type=${type} edge=${edgeName} grow=${grow} current=${size.grid_x},${size.grid_y},${size.lane_w}x${size.lane_h} widthLimit=${widthLimit} maxH=${this.maxCompH} cols=${this.LayoutWidth()}`)
    if (edge === ResizeEdge.Left) {
      nextW = Math.max(1, Math.min(widthLimit, size.lane_w + delta))
      nextX = size.grid_x - (nextW - size.lane_w)
    } else if (edge === ResizeEdge.Right) {
      nextW = Math.max(1, Math.min(widthLimit, size.lane_w + delta))
    } else if (edge === ResizeEdge.Up) {
      nextH = Math.max(1, Math.min(this.maxCompH, size.lane_h + delta))
      nextY = size.grid_y - (nextH - size.lane_h)
    } else {
      nextH = Math.max(1, Math.min(this.maxCompH, size.lane_h + delta))
    }
    if (nextW === size.lane_w && nextH === size.lane_h && nextX === size.grid_x && nextY === size.grid_y) {
      desktopLayoutDebug(`resize rejected unchanged type=${type} edge=${edgeName} target=${nextX},${nextY},${nextW}x${nextH}`)
      return false
    }
    if (this.isOutOfBounds(nextX, nextY, nextW, nextH)) {
      desktopLayoutDebug(`resize rejected outOfBounds type=${type} edge=${edgeName} target=${nextX},${nextY},${nextW}x${nextH} layout=${this.LayoutWidth()}x${this.LayoutHeight()}`)
      return false
    }
    const target: Position = { x: nextX, y: nextY }
    const occupied: Map<string, GridRect> = new Map()
    const nextMap: Map<string, Position> = new Map()
    occupied.set(type, { x: nextX, y: nextY, w: nextW, h: nextH })
    for (const comp of this.comp_sequence) {
      if (comp === type) {
        continue
      }
      const compSize = this.getCompSize(comp)
      const origin: Position = { x: compSize.grid_x, y: compSize.grid_y }
      if (this.canPlaceAgainstMap(origin.x, origin.y, compSize.lane_w, compSize.lane_h, occupied)) {
        occupied.set(comp, { x: origin.x, y: origin.y, w: compSize.lane_w, h: compSize.lane_h })
        nextMap.set(comp, origin)
        continue
      }
      const free = this.findNearestFreeSpace(compSize.lane_w, compSize.lane_h, occupied, origin, target)
      if (free.x < 0 || free.y < 0) {
        desktopLayoutDebug(`resize rejected noFreeSpace type=${type} edge=${edgeName} obstacle=${comp} target=${nextX},${nextY},${nextW}x${nextH}`)
        return false
      }
      occupied.set(comp, { x: free.x, y: free.y, w: compSize.lane_w, h: compSize.lane_h })
      nextMap.set(comp, free)
    }
    nextMap.forEach((pos: Position, comp: string) => {
      const compSize = this.getCompSize(comp)
      if (pos.x !== compSize.grid_x || pos.y !== compSize.grid_y) {
        this.animateVisualOffset(compSize, pos)
      }
    })
    size.grid_x = nextX
    size.grid_y = nextY
    size.lane_w = nextW
    size.lane_h = nextH
    size.resetResizeOffsets()
    size.next_grid_x = nextX
    size.next_grid_y = nextY
    size.find_next_grid = false
    size.isResize = true
    nextMap.forEach((pos: Position, comp: string) => {
      const compSize = this.getCompSize(comp)
      compSize.grid_x = pos.x
      compSize.grid_y = pos.y
      compSize.next_grid_x = pos.x
      compSize.next_grid_y = pos.y
      compSize.find_next_grid = false
    })
    this.updateSequence()
    desktopLayoutDebug(`resize applied type=${type} edge=${edgeName} target=${nextX},${nextY},${nextW}x${nextH} moved=${nextMap.size}`)
    return true
  }

  triggerDropWave(dropType: string, drop: Position) {
    this.comp_sequence.forEach((type: string) => {
      if (type === dropType) {
        return
      }
      const size = this.getCompSize(type)
      const centerX = size.grid_x + size.lane_w / 2
      const centerY = size.grid_y + size.lane_h / 2
      const dx = centerX - drop.x
      const dy = centerY - drop.y
      const distance = Math.sqrt(dx * dx + dy * dy)
      const directionX = distance > 0.01 ? dx / distance : 0
      const directionY = distance > 0.01 ? dy / distance : -1
      const delay = Math.min(DROP_WAVE_MAX_DELAY, Math.floor(distance * 95))
      const magnitude = Math.max(DROP_WAVE_MIN_OFFSET, DROP_WAVE_MAX_OFFSET - distance * 3.2)
      const rebound = Math.max(0.8, magnitude * DROP_WAVE_REBOUND_RATIO)
      const targetX = directionX * magnitude
      const targetY = directionY * magnitude
      const reboundX = -directionX * rebound
      const reboundY = -directionY * rebound
      size.wave_anim_id = size.wave_anim_id + 1
      const animId = size.wave_anim_id
      desktopLayoutDebug(`dropWave type=${type} from=${drop.x},${drop.y} center=${centerX},${centerY} distance=${distance} delay=${delay} offset=${targetX},${targetY}`)
      setTimeout(() => {
        if (size.wave_anim_id !== animId) {
          return
        }
        animateToImmediately({
          duration: 155,
          curve: curves.cubicBezierCurve(0.18, 0.0, 0.12, 1.0),
          onFinish: () => {
            if (size.wave_anim_id !== animId) {
              return
            }
            animateToImmediately({
              duration: 115,
              curve: curves.cubicBezierCurve(0.20, 0.0, 0.0, 1.0),
              onFinish: () => {
                if (size.wave_anim_id !== animId) {
                  return
                }
                animateToImmediately({
                  duration: 220,
                  curve: Curve.Friction
                }, () => {
                  if (size.wave_anim_id !== animId) {
                    return
                  }
                  size.waveScale = 1
                  size.waveOffsetX = 0
                  size.waveOffsetY = 0
                })
              }
            }, () => {
              if (size.wave_anim_id !== animId) {
                return
              }
              size.waveScale = 0.998
              size.waveOffsetX = reboundX
              size.waveOffsetY = reboundY
            })
          }
        }, () => {
          if (size.wave_anim_id !== animId) {
            return
          }
          size.waveScale = 1.035
          size.waveOffsetX = targetX
          size.waveOffsetY = targetY
        })
      }, delay)
    })
  }

  lane(need: number): number {
    const scale = Math.min(this.currentColCount, Math.max(1, need))
    const innerWidth = Math.max(0, this.comp_width - this.padding * 2)
    if (scale === this.currentColCount) {
      return innerWidth
    }
    const singleLane = this.preciseIntegerDivision(innerWidth - (this.currentColCount - 1) * this.gap,
      this.currentColCount)
    return singleLane * scale + (scale - 1) * this.gap
  }

  preciseIntegerDivision(a: number, b: number): number {
    const result = a / b
    if (Math.abs(result - Math.round(result)) < 1e-10) {
      return Math.round(result)
    }
    return result
  }

  dispose() {
    this.compSizeMap.clear()
    this.comp_sequence = []
    this.comp_types = []
    this.widgetList = []
    this.draggingType = ''
    this.bumpRevision()
  }
}

@ComponentV2
struct DesktopGridContentHost {
  @Param @Require comp_type: string
  @Param @Require layout: LayoutUtil
  @Param @Require contentBuilder: WrappedBuilder<[string]>
  @Local comp_size: CompSize = this.layout.getCompSize(this.comp_type)
  @Provider('w') w: number = this.comp_size.lane_w
  @Provider('h') h: number = this.comp_size.lane_h

  @Monitor('comp_size.lane_w', 'comp_size.lane_h')
  onCompSizeChange() {
    this.w = this.comp_size.lane_w
    this.h = this.comp_size.lane_h
  }

  build() {
    this.contentBuilder.builder(this.comp_type)
  }
}

@ComponentV2
struct ResizeHandle {
  @Param @Require comp_type: string
  @Param @Require layout: LayoutUtil
  @Param @Require edge: ResizeEdge
  @Param hitWidth: number = RESIZE_HANDLE_SIZE
  @Param hitHeight: number = RESIZE_HANDLE_SIZE
  @Param ballCenterX: number = RESIZE_HANDLE_OFFSET
  @Param ballCenterY: number = RESIZE_HANDLE_OFFSET
  @Local fingerOffset: number = 0
  @Local disableGrow: boolean = false
  @Local disableShrink: boolean = false

  private compSize(): CompSize {
    return this.layout.getCompSize(this.comp_type)
  }

  private beginResize(renewGuard: boolean = false) {
    const size = this.compSize()
    if (renewGuard || !size.isResizing) {
      size.resize_guard_id = size.resize_guard_id + 1
      size.resetResizeOffsets()
      this.fingerOffset = 0
      this.disableGrow = false
      this.disableShrink = false
    }
    size.isResizing = true
    size.isResize = true
    size.isDragging = false
  }

  private endResize() {
    const size = this.compSize()
    const guardId = size.resize_guard_id
    desktopLayoutDebug(`resize handle end type=${this.comp_type} edge=${resizeEdgeName(this.edge)} guard=${guardId}`)
    animateToImmediately(layoutAnimationParam, () => {
      size.resetResizeOffsets()
    })
    this.fingerOffset = 0
    this.disableGrow = false
    this.disableShrink = false
    setTimeout(() => {
      if (size.resize_guard_id === guardId) {
        size.isResizing = false
      }
    }, 32)
  }

  private rawOffset(event: GestureEvent): number {
    if (this.edge === ResizeEdge.Left || this.edge === ResizeEdge.Right) {
      return event.offsetX
    }
    return event.offsetY
  }

  private normalizedOffset(event: GestureEvent): number {
    const rawOffset = this.rawOffset(event) - this.fingerOffset
    if (this.edge === ResizeEdge.Left) {
      return -rawOffset
    }
    if (this.edge === ResizeEdge.Right) {
      return rawOffset
    }
    if (this.edge === ResizeEdge.Up) {
      return -rawOffset
    }
    return rawOffset
  }

  private setLiveOffset(offset: number) {
    const size = this.compSize()
    if (this.edge === ResizeEdge.Left) {
      size.offset_l = offset
    } else if (this.edge === ResizeEdge.Right) {
      size.offset_r = offset
    } else if (this.edge === ResizeEdge.Up) {
      size.offset_u = offset
    } else {
      size.offset_d = offset
    }
  }

  private clearLiveOffset() {
    this.setLiveOffset(0)
  }

  private resizeSign(): number {
    if (this.edge === ResizeEdge.Left || this.edge === ResizeEdge.Up) {
      return -1
    }
    return 1
  }

  private applyResizeStep(rawOffset: number, normalizedOffset: number, grow: boolean): boolean {
    const moved = this.layout.resizeComponent(this.comp_type, this.edge, grow)
    if (moved) {
      this.disableGrow = false
      this.disableShrink = false
      const period = Math.max(1, this.layout.lane(1) + this.layout.gap)
      const residualOffset = grow ? normalizedOffset - period : normalizedOffset + period
      this.fingerOffset = rawOffset - residualOffset / this.resizeSign()
      this.setLiveOffset(residualOffset)
    } else if (grow) {
      this.fingerOffset = rawOffset
      this.clearLiveOffset()
      this.disableGrow = true
    } else {
      this.fingerOffset = rawOffset
      this.clearLiveOffset()
      this.disableShrink = true
    }
    return moved
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
      Circle({ width: 22, height: 22 })
        .fill('#3A0A59F7')
        .position({ x: this.ballCenterX - 11, y: this.ballCenterY - 11 })
      Circle({ width: 9, height: 9 })
        .fill($r('sys.color.brand'))
        .position({ x: this.ballCenterX - 4.5, y: this.ballCenterY - 4.5 })
    }
    .width(this.hitWidth)
    .height(this.hitHeight)
    .alignContent(Alignment.Center)
    .gesture(PanGesture({
      direction: this.edge === ResizeEdge.Left || this.edge === ResizeEdge.Right ?
      PanDirection.Horizontal : PanDirection.Vertical,
      fingers: 1,
      distance: 1
    })
      .onActionStart(() => {
        this.beginResize(true)
        const size = this.compSize()
        desktopLayoutDebug(`resize pan start type=${this.comp_type} edge=${resizeEdgeName(this.edge)} size=${size.lane_w}x${size.lane_h} pos=${size.grid_x},${size.grid_y} hit=${this.hitWidth}x${this.hitHeight} ball=${this.ballCenterX},${this.ballCenterY}`)
      })
      .onActionUpdate((event: GestureEvent) => {
        this.beginResize()
        const rawOffset = this.rawOffset(event)
        const normalizedOffset = this.normalizedOffset(event)
        if (normalizedOffset >= 0 && this.disableGrow) {
          this.fingerOffset = rawOffset
          desktopLayoutDebug(`resize pan update blockedGrow type=${this.comp_type} edge=${resizeEdgeName(this.edge)} raw=${rawOffset} normalized=${normalizedOffset}`)
          return
        }
        if (normalizedOffset < 0 && this.disableShrink) {
          this.fingerOffset = rawOffset
          desktopLayoutDebug(`resize pan update blockedShrink type=${this.comp_type} edge=${resizeEdgeName(this.edge)} raw=${rawOffset} normalized=${normalizedOffset}`)
          return
        }
        if (normalizedOffset >= 0) {
          this.disableShrink = false
        } else {
          this.disableGrow = false
        }

        const laneSize = Math.max(1, this.layout.lane(1))
        const growThreshold = laneSize * 0.6 + 10
        const shrinkThreshold = -(laneSize * 0.5 + 10)
        desktopLayoutDebug(`resize pan update type=${this.comp_type} edge=${resizeEdgeName(this.edge)} raw=${rawOffset} normalized=${normalizedOffset} growThreshold=${growThreshold} shrinkThreshold=${shrinkThreshold}`)
        if (normalizedOffset >= growThreshold) {
          const moved = this.applyResizeStep(rawOffset, normalizedOffset, true)
          desktopLayoutDebug(`resize pan step ${moved ? 'applied' : 'blocked'} type=${this.comp_type} edge=${resizeEdgeName(this.edge)} grow=true`)
        } else if (normalizedOffset <= shrinkThreshold) {
          const moved = this.applyResizeStep(rawOffset, normalizedOffset, false)
          desktopLayoutDebug(`resize pan step ${moved ? 'applied' : 'blocked'} type=${this.comp_type} edge=${resizeEdgeName(this.edge)} grow=false`)
        } else {
          this.setLiveOffset(normalizedOffset)
        }
      })
      .onActionEnd(() => {
        desktopLayoutDebug(`resize pan actionEnd type=${this.comp_type} edge=${resizeEdgeName(this.edge)}`)
        this.endResize()
      })
      .onActionCancel(() => {
        desktopLayoutDebug(`resize pan actionCancel type=${this.comp_type} edge=${resizeEdgeName(this.edge)}`)
        this.endResize()
      }))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        desktopLayoutDebug(`resize touch down type=${this.comp_type} edge=${resizeEdgeName(this.edge)}`)
        this.beginResize(true)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        desktopLayoutDebug(`resize touch end type=${this.comp_type} edge=${resizeEdgeName(this.edge)} touchType=${event.type}`)
        this.endResize()
      }
      event.stopPropagation()
    })
    .monopolizeEvents(true)
    .zIndex(RESIZE_HANDLE_Z_INDEX)
    .hitTestBehavior(HitTestMode.Block)
  }
}

@ComponentV2
struct DesktopGridFloatingCard {
  @Param @Require comp_type: string
  @Param @Require layout: LayoutUtil
  @Param @Require contentBuilder: WrappedBuilder<[string]>

  @Computed
  get compSize(): CompSize {
    return this.layout.getCompSize(this.comp_type)
  }

  @Computed
  get period(): number {
    return this.layout.lane(1) + this.layout.gap
  }

  build() {
    Column() {
      DesktopGridContentHost({
        comp_type: this.comp_type,
        layout: this.layout,
        contentBuilder: this.contentBuilder
      })
    }
    .width(this.layout.lane(this.compSize.lane_w))
    .height(this.layout.lane(this.compSize.lane_h))
    .borderRadius(CARD_RADIUS)
    .clip(true)
    .position({
      x: this.compSize.grid_x * this.period + this.compSize.pan_offset_x,
      y: this.compSize.grid_y * this.period + this.compSize.pan_offset_y
    })
    .scale({ x: 1.04, y: 1.04 })
    .opacity(0.96)
    .shadow({
      radius: 18,
      color: '#33000000',
      offsetY: 8
    })
    .zIndex(100)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

@ComponentV2
struct DesktopGridCard {
  @Param @Require comp_type: string
  @Param @Require layout: LayoutUtil
  @Param @Require contentBuilder: WrappedBuilder<[string]>
  @Local comp_size: CompSize = this.layout.getCompSize(this.comp_type)
  @Local openMenu: boolean = false

  @Computed
  get cardWidth(): number {
    return this.layout.lane(this.comp_size.lane_w)
  }

  @Computed
  get cardHeight(): number {
    return this.layout.lane(this.comp_size.lane_h)
  }

  @Computed
  get resizeOffsetW(): number {
    return this.comp_size.offset_l + this.comp_size.offset_r
  }

  @Computed
  get resizeOffsetH(): number {
    return this.comp_size.offset_u + this.comp_size.offset_d
  }

  @Computed
  get visualCardWidth(): number {
    return Math.max(1, this.cardWidth + this.resizeOffsetW)
  }

  @Computed
  get visualCardHeight(): number {
    return Math.max(1, this.cardHeight + this.resizeOffsetH)
  }

  @Computed
  get visualCardX(): number {
    return -this.comp_size.offset_l
  }

  @Computed
  get visualCardY(): number {
    return -this.comp_size.offset_u
  }

  private startEdit() {
    if (this.comp_size.isDragging) {
      desktopLayoutDebug(`startEdit ignored dragging type=${this.comp_type}`)
      return
    }
    this.layout.closeEditingExcept(this.comp_type)
    this.comp_size.isResize = true
    desktopLayoutDebug(`startEdit type=${this.comp_type} pos=${this.comp_size.grid_x},${this.comp_size.grid_y} size=${this.comp_size.lane_w}x${this.comp_size.lane_h} card=${this.cardWidth}x${this.cardHeight}`)
    if (canIUse('SystemCapability.Sensors.MiscDevice')) {
      vibrator.startVibration({
        type: 'time',
        duration: 1
      }, {
        id: 0,
        usage: 'touch'
      }, () => {})
    }
    setTimeout(() => {
      if (!this.comp_size.isDragging && this.comp_size.isResize) {
        this.openMenu = true
      }
    }, 1)
  }

  private startDrag() {
    if (this.comp_size.isResizing) {
      desktopLayoutDebug(`startDrag ignored resizing type=${this.comp_type}`)
      return
    }
    if (!this.comp_size.isResize && !this.comp_size.isDragging) {
      desktopLayoutDebug(`startDrag ignored notEditing type=${this.comp_type}`)
      return
    }
    this.openMenu = false
    const started = this.layout.beginDrag(this.comp_type)
    desktopLayoutDebug(`startDrag type=${this.comp_type} started=${started}`)
  }

  @Computed
  get moveLayerInset(): number {
    return this.comp_size.isResize ? RESIZE_TOUCH_INSET : 0
  }

  @Computed
  get moveLayerWidth(): number {
    return Math.max(1, this.visualCardWidth - this.moveLayerInset * 2)
  }

  @Computed
  get moveLayerHeight(): number {
    return Math.max(1, this.visualCardHeight - this.moveLayerInset * 2)
  }

  private shouldBlockTouch(): boolean {
    return this.comp_size.isResize || this.comp_size.isDragging
  }

  private isCenterMoveGesture(event: BaseGestureEvent): boolean {
    if (event.fingerList.length <= 0) {
      return true
    }
    const period = this.layout.lane(1) + this.layout.gap
    const cardLeft = this.layout.desktopPosX + this.layout.padding + this.layout.displayGridX(this.comp_size) * period
    const cardTop = this.layout.desktopPosY + this.layout.padding + this.layout.displayGridY(this.comp_size) * period
    const localX = event.fingerList[0].globalX - cardLeft
    const localY = event.fingerList[0].globalY - cardTop
    const result = localX >= RESIZE_TOUCH_INSET &&
      localX <= this.cardWidth - RESIZE_TOUCH_INSET &&
      localY >= RESIZE_TOUCH_INSET &&
      localY <= this.cardHeight - RESIZE_TOUCH_INSET
    desktopLayoutDebug(`centerMoveJudge type=${this.comp_type} local=${localX},${localY} card=${this.cardWidth}x${this.cardHeight} result=${result}`)
    return result
  }

  @Builder
  CardMenu() {
    Menu() {
      if (deviceInfo.sdkApiVersion >= 18 && this.layout.widgetList.includes(this.comp_type)) {
        MenuItem({
          symbolStartIcon: symbolWithSize($r('sys.symbol.plus_square'), 24),
          content: '添加到桌面'
        })
          .onClick(() => {
            this.openMenu = false
            try {
              formProvider.openFormManager(this.layout.formWantFunc(this.comp_type))
            } catch (_) {
            }
          })
      }
      MenuItem({
        symbolStartIcon: symbolWithSize($r('sys.symbol.eye_slash'), 24),
        content: '隐藏组件'
      })
        .onClick(() => {
          this.openMenu = false
          animateToImmediately({
            duration: 220,
            curve: Curve.EaseInOut
          }, () => {
            this.comp_size.willHide = true
            this.comp_size.waveScale = 0.92
          })
          setTimeout(() => {
            this.layout.removeComponent(this.comp_type)
          }, 180)
        })
    }
  }

  @Builder
  MoveTouchLayer() {
    Column()
      .width(this.moveLayerWidth)
      .height(this.moveLayerHeight)
      .position({
        x: this.visualCardX + this.moveLayerInset,
        y: this.visualCardY + this.moveLayerInset
      })
      .backgroundColor(Color.Transparent)
      .gesture(GestureGroup(GestureMode.Sequence,
        LongPressGesture({ repeat: false, fingers: 1, duration: 300 })
          .onAction(() => {
            if (!this.comp_size.isResizing) {
              desktopLayoutDebug(`move longPress type=${this.comp_type}`)
              this.startEdit()
            } else {
              desktopLayoutDebug(`move longPress ignored resizing type=${this.comp_type}`)
            }
          }),
        PanGesture({ direction: PanDirection.All, fingers: 1, distance: MOVE_DRAG_DISTANCE })
          .onActionStart((event: GestureEvent) => {
            desktopLayoutDebug(`move pan start type=${this.comp_type} offset=${event.offsetX},${event.offsetY}`)
            if (this.isCenterMoveGesture(event)) {
              this.startDrag()
            } else {
              desktopLayoutDebug(`move pan start rejected outside center type=${this.comp_type}`)
            }
          })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.comp_size.isResizing && this.comp_size.isDragging) {
              desktopLayoutDebug(`move pan update type=${this.comp_type} offset=${event.offsetX},${event.offsetY}`)
              this.layout.updateDrag(this.comp_type, event.offsetX, event.offsetY)
            } else {
              desktopLayoutDebug(`move pan update ignored type=${this.comp_type} resizing=${this.comp_size.isResizing} dragging=${this.comp_size.isDragging}`)
            }
          })
          .onActionEnd(() => {
            desktopLayoutDebug(`move pan end type=${this.comp_type} dragging=${this.comp_size.isDragging} resizing=${this.comp_size.isResizing}`)
            if (this.comp_size.isDragging) {
              if (this.comp_size.isResizing) {
                this.layout.cancelTempPos()
              } else {
                this.layout.confirmTempPos()
              }
            }
          })
          .onActionCancel(() => {
            desktopLayoutDebug(`move pan cancel type=${this.comp_type} dragging=${this.comp_size.isDragging}`)
            if (this.comp_size.isDragging) {
              this.layout.cancelTempPos()
            }
          })
      ))
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down && !this.shouldBlockTouch()) {
          desktopLayoutDebug(`move touch down passThrough type=${this.comp_type}`)
          this.layout.closeEditingExcept(this.comp_type)
        }
        if (this.shouldBlockTouch()) {
          desktopLayoutDebug(`move touch block type=${this.comp_type} touchType=${event.type} edit=${this.comp_size.isResize} dragging=${this.comp_size.isDragging}`)
          event.stopPropagation()
        }
      })
      .zIndex(MOVE_LAYER_Z_INDEX)
      .hitTestBehavior(this.shouldBlockTouch() ? HitTestMode.Block : HitTestMode.Transparent)
  }

  @Builder
  ResizeBorder() {
    Column()
      .width(this.visualCardWidth)
      .height(this.visualCardHeight)
      .borderWidth(2)
      .borderColor($r('sys.color.brand'))
      .borderRadius(CARD_RADIUS)
      .position({ x: this.visualCardX, y: this.visualCardY })
      .clip(false)
      .zIndex(RESIZE_CHROME_Z_INDEX)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  ResizeHandles() {
    ResizeHandle({
      comp_type: this.comp_type,
      layout: this.layout,
      edge: ResizeEdge.Left,
      hitWidth: RESIZE_TOUCH_BAND_SIZE,
      hitHeight: this.visualCardHeight,
      ballCenterX: RESIZE_HANDLE_OFFSET + RESIZE_BALL_INSET,
      ballCenterY: this.visualCardHeight / 2
    })
      .position({ x: this.visualCardX - RESIZE_HANDLE_OFFSET, y: this.visualCardY })
      .zIndex(RESIZE_HANDLE_Z_INDEX)
    ResizeHandle({
      comp_type: this.comp_type,
      layout: this.layout,
      edge: ResizeEdge.Right,
      hitWidth: RESIZE_TOUCH_BAND_SIZE,
      hitHeight: this.visualCardHeight,
      ballCenterX: RESIZE_TOUCH_INSET - RESIZE_BALL_INSET,
      ballCenterY: this.visualCardHeight / 2
    })
      .position({ x: this.visualCardX + this.visualCardWidth - RESIZE_TOUCH_INSET, y: this.visualCardY })
      .zIndex(RESIZE_HANDLE_Z_INDEX)
    ResizeHandle({
      comp_type: this.comp_type,
      layout: this.layout,
      edge: ResizeEdge.Up,
      hitWidth: this.visualCardWidth,
      hitHeight: RESIZE_TOUCH_BAND_SIZE,
      ballCenterX: this.visualCardWidth / 2,
      ballCenterY: RESIZE_HANDLE_OFFSET + RESIZE_BALL_INSET
    })
      .position({ x: this.visualCardX, y: this.visualCardY - RESIZE_HANDLE_OFFSET })
      .zIndex(RESIZE_HANDLE_Z_INDEX)
    ResizeHandle({
      comp_type: this.comp_type,
      layout: this.layout,
      edge: ResizeEdge.Down,
      hitWidth: this.visualCardWidth,
      hitHeight: RESIZE_TOUCH_BAND_SIZE,
      ballCenterX: this.visualCardWidth / 2,
      ballCenterY: RESIZE_TOUCH_INSET - RESIZE_BALL_INSET
    })
      .position({ x: this.visualCardX, y: this.visualCardY + this.visualCardHeight - RESIZE_TOUCH_INSET })
      .zIndex(RESIZE_HANDLE_Z_INDEX)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.comp_size.isDragging) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('sys.color.font_on_fourth'))
          .borderWidth(2)
          .borderColor($r('sys.color.font_on_tertiary'))
          .borderRadius(CARD_RADIUS)
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            DesktopGridContentHost({
              comp_type: this.comp_type,
              layout: this.layout,
              contentBuilder: this.contentBuilder
            })
          }
          .width('100%')
          .height('100%')
          .borderRadius(CARD_RADIUS)
          .clip(true)
          Column()
            .width('100%')
            .height('100%')
            .borderRadius(CARD_RADIUS)
            .borderWidth(0.5)
            .borderColor('#12000000')
            .hitTestBehavior(HitTestMode.None)
        }
        .width(this.visualCardWidth)
        .height(this.visualCardHeight)
        .position({ x: this.visualCardX, y: this.visualCardY })
        .backgroundColor($r('sys.color.comp_background_primary'))
        .borderRadius(CARD_RADIUS)
        .shadow({
          radius: this.comp_size.isResize ? 18 : 12,
          color: this.comp_size.isResize ? '#220A59F7' : '#18000000',
          offsetY: this.comp_size.isResize ? 6 : 4
        })
        .clip(false)
        .bindContextMenu(this.openMenu, this.CardMenu, {
          placement: Placement.TopRight,
          onDisappear: () => {
            this.openMenu = false
          }
        })
      }
      this.MoveTouchLayer()
      if (this.comp_size.isResize && !this.comp_size.isDragging) {
        this.ResizeBorder()
        this.ResizeHandles()
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(CARD_RADIUS)
    .clip(false)
    .opacity(this.comp_size.willHide ? 0 : 1)
    .scale({
      x: this.comp_size.waveScale,
      y: this.comp_size.waveScale
    })
    .animation(layoutAnimationParam)
    .translate({
      x: this.comp_size.visual_offset_x + this.comp_size.waveOffsetX,
      y: this.comp_size.visual_offset_y + this.comp_size.waveOffsetY
    })
    .zIndex(this.comp_size.isDragging ? 100 : (this.comp_size.isResize ? 90 : 1))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down && !this.shouldBlockTouch()) {
        this.layout.closeEditingExcept(this.comp_type)
      }
      if (this.shouldBlockTouch()) {
        event.stopPropagation()
      }
    })
    .hitTestBehavior(this.shouldBlockTouch() ? HitTestMode.Default : HitTestMode.Transparent)
  }
}

@ComponentV2
export struct DesktopLayout {
  @Param comp_sequence: CompSizeWithPos[] = []
  @Param types: string[] = []
  @Param saveSequence: (layout: LayoutUtil) => void = () => {}
  @Param contentBuilder: WrappedBuilder<[string]> = wrapBuilder(contentComp)
  @Param name: string = 'index'
  @Param hasWidgetList: string[] = []
  @Param formWantFunc: (comp_type: string) => Want = (comp_type: string) => {
    return {
      bundleName: APP_BUNDLE_NAME,
      abilityName: ENTRY_FORM_ABILITY_NAME,
      parameters: {
        'ohos.extra.param.key.form_dimension': 1,
        'ohos.extra.param.key.form_name': comp_type,
        'ohos.extra.param.key.module_name': 'entry'
      }
    }
  }
  @Param breakpoints: BreakpointConfig[] = [
    { breakpoint: 0, columns: 2 },
    { breakpoint: 720, columns: 4 },
    { breakpoint: 1080, columns: 6 }
  ]
  @Param maxCompW: number = 6
  @Param maxCompH: number = 6
  @Provider('layout') layout: LayoutUtil = new LayoutUtil(this.name, this.comp_sequence, this.types, this.saveSequence,
    this.contentBuilder, this.hasWidgetList, this.formWantFunc, this.breakpoints, this.maxCompW, this.maxCompH)

  aboutToDisappear(): void {
    LayoutManager.unregisterLayout(this.name)
    this.layout.dispose()
  }

  @Computed
  get CompSizes(): CompSize[] {
    return this.layout.comp_sequence.map((value: string) => this.layout.getCompSize(value))
  }

  @Computed
  get gridLayoutOptions(): GridLayoutOptions {
    const revision = this.layout.revision
    if (revision < 0) {
      return { regularSize: [1, 1] }
    }
    desktopLayoutDebug(`gridLayoutOptions revision=${revision} count=${this.layout.comp_sequence.length}`)
    return {
      regularSize: [1, 1],
      onGetRectByIndex: (index: number) => {
        if (index < 0 || index >= this.layout.comp_sequence.length) {
          return [0, 0, 1, 1]
        }
        const size = this.layout.getCompSize(this.layout.comp_sequence[index])
        desktopLayoutDebug(`gridRect index=${index} type=${size.type} rect=${this.layout.displayGridY(size)},${this.layout.displayGridX(size)},${size.lane_h},${size.lane_w} revision=${this.layout.revision}`)
        return [
          this.layout.displayGridY(size),
          this.layout.displayGridX(size),
          Math.max(1, size.lane_h),
          Math.max(1, size.lane_w)
        ]
      }
    }
  }

  private repeatFr(count: number): string {
    let result = '1fr'
    for (let i = 1; i < count; i++) {
      result += ' 1fr'
    }
    return result
  }

  @Computed
  get columnsTemplate(): string {
    return this.repeatFr(this.layout.LayoutWidth())
  }

  @Computed
  get rowsTemplate(): string {
    return this.repeatFr(this.layout.VisibleRows())
  }

  @Computed
  get gridHeight(): number {
    const rows = this.layout.VisibleRows()
    return rows * this.layout.lane(1) + Math.max(0, rows - 1) * this.layout.gap
  }

  @Computed
  get layoutHeight(): number {
    return this.gridHeight + this.layout.padding * 2
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Grid(undefined, this.gridLayoutOptions) {
          ForEach(this.CompSizes, (size: CompSize) => {
            GridItem() {
              DesktopGridCard({
                comp_type: size.type,
                layout: this.layout,
                contentBuilder: this.contentBuilder
              })
            }
            .width('100%')
            .height('100%')
            .clip(false)
            .zIndex(size.isDragging ? 100 : (size.isResize ? 90 : (size.find_next_grid ? 50 : 1)))
          }, (item: CompSize) => item.type)
        }
        .columnsTemplate(this.columnsTemplate)
        .rowsTemplate(this.rowsTemplate)
        .columnsGap(this.layout.gap)
        .rowsGap(this.layout.gap)
        .supportAnimation(false)
        .width('100%')
        .height(this.gridHeight)
        .clip(false)
        .hitTestBehavior(this.layout.draggingType.length > 0 ? HitTestMode.Block : HitTestMode.Transparent)

        if (this.layout.draggingType.length > 0) {
          DesktopGridFloatingCard({
            comp_type: this.layout.draggingType,
            layout: this.layout,
            contentBuilder: this.contentBuilder
          })
        }
      }
      .width('100%')
      .height(this.gridHeight)
      .clip(false)
    }
    .width('100%')
    .height(this.layoutHeight)
    .padding({
      top: this.layout.padding,
      left: this.layout.padding,
      right: this.layout.padding,
      bottom: this.layout.padding
    })
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down && this.layout.draggingType.length === 0) {
        this.layout.closeEditingExcept()
      }
    })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.layout.desktopPosX = newArea.globalPosition.x!.valueOf() as number
      this.layout.desktopPosY = newArea.globalPosition.y!.valueOf() as number
      this.layout.desktopWidth = newArea.width.valueOf() as number
      this.layout.desktopHeight = newArea.height.valueOf() as number
      this.layout.updateDisplaySize(newArea.width.valueOf() as number, newArea.height.valueOf() as number)
      desktopLayoutDebug(`desktop area x=${this.layout.desktopPosX} y=${this.layout.desktopPosY} w=${this.layout.desktopWidth} h=${this.layout.desktopHeight}`)
    })
  }
}
