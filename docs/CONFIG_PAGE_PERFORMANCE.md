# 配置页加载与 BoolField 渲染性能说明

## 目标与边界

本次改动包含两条彼此独立的工作线：

1. **配置页渐进加载**：降低进入配置编辑页时同一帧创建、测量大量 ArkUI 节点造成的卡顿。
2. **C++ BoolField 文本子树**：缩短 BoolField 自定义组件的构建时间。

Core 的 Rust crate 拆分用于明确配置功能、内核运行时和 N-API 外观层的职责，不作为 ArkUI 帧耗时优化结论。C++ 实现仍通过 ArkUI Native Node 创建节点，不是独立渲染器，也没有把 ArkUI Layout 移到后台线程。

## 实现

### 渐进加载

- `EditPage` 先解析分区计划，只优先加载并挂载当前可见窗口。
- 平板三栏 `Swiper` 的可见分区、后续预加载分区、分区行和递归 group 共用一个全页 FIFO 帧调度器。
- 每次 frame callback 只放行一个工作项，避免多个组件各自拥有“每帧预算”并在同一帧叠加。
- 分区行使用 `LazyForEach`；BoolField 行和 `ListItem` 使用确定高度，减少递归内容测量。
- 离屏 `ListField` 值不进入全局队列。实测离屏节点不产生 dirty frame，会让依赖 `postFrameCallback` 的队列饥饿。
- 没有保留 timer watchdog 或纯 `onIdle` 调度：设备上 16 ms timer 被节流到约 250 ms；`onIdle` 在页面切换动画期间又会等待约 300 ms 的空闲窗口。

### Native BoolField

ArkTS 继续负责：

- 卡片容器、两列布局和点击动画；
- `SymbolGlyph`；
- 配置读写、选中状态和生命周期。

C++ 仅负责原先每张卡片中的两个 ArkTS `Text` 节点，创建一个 Native `Column + Text + Text` 子树并挂入 `NodeContent`。实现特性：

- 每个 N-API `env` 独立保存 native 节点记录；
- 所有 Native Node 属性写入都检查返回值；
- 创建或资源解析失败时销毁部分节点并回退到原 ArkTS 文本；
- 更新和销毁路径分别带有 `ET_BOOL_NATIVE_UPDATE`、`ET_BOOL_NATIVE_DESTROY` trace；
- Native Node API 没有 `SymbolGlyph`，因此图标刻意保留在 ArkTS。

## 真机测量方法

设备分辨率为 2800×1840，构建目标 API 23，使用签名 Debug HAP。采集命令：

```text
hitrace --trace_begin -b 65536 app ace graphic ability
```

主要对比：

- `CustomNode:BuildItem [BoolField]`；
- UI 线程 `ReceiveVsync` 同步区间；
- `ET_BOOL_NATIVE_CREATE`；
- 系统 `ABILITY_OR_PAGE_SWITCH` 的 response/e2e/jank 报告。

本地原始证据：

- `/tmp/easytier-global-budget-v3.trace`
- `/tmp/easytier-native-v7.trace`
- `/tmp/easytier-arkts-true-control.trace`

## 结果

### 页面渐进加载

本表使用 ArkTS BoolField 隔离渐进加载/全页调度本身的收益；C++ A/B 在下一节单独计算，避免把两条工作线混为一个结论。

| 版本 | response | e2e | 系统上报 max frame |
| --- | ---: | ---: | ---: |
| 原始基线 | 55 ms | 814 ms | 101 ms |
| 渐进加载 v2 | 95 ms | 671 ms | 57 ms |
| 全页预算 v3 | 81 ms | 622 ms | 33 ms |

相对原始基线，全页预算版本把 e2e 缩短约 23.6%，系统上报的最大帧由 101 ms 降至 33 ms。

### BoolField ArkTS/C++ A/B

下表使用原 ArkTS BoolField 真对照和最终 native 实现；两边都构建 20 个 BoolField：

| 指标 | 原 ArkTS | C++ 文本子树 | 变化 |
| --- | ---: | ---: | ---: |
| BoolField BuildItem 总时间 | 44.427 ms | 28.148 ms | -36.6% |
| BoolField BuildItem 最大值 | 3.395 ms | 2.405 ms | -29.2% |
| UI frame p95 | 26.553 ms | 18.663 ms | -29.7% |
| UI frame 最大执行时间 | 33.686 ms | 34.510 ms | +0.824 ms |

最终 native run 中，20 次 `ET_BOOL_NATIVE_CREATE` 合计 3.608 ms，中位数 0.163 ms，最大值 0.475 ms。

该结果支持“C++ 让 BoolField 构建更快”，但不把其他 `Swiper`/`List` 布局成本归因于 BoolField。整体最大 UI 执行时间仍由外层列表和分区布局决定。

## 关于系统 max-frame 数值

部分后续 run 的 `INTERACTION_APP_JANK.maxFrameTime` 报告约 217–220 ms，但相同区间内 UI 线程最长 `ReceiveVsync` 只有约 34 ms。trace 显示这些大值是渐进工作之间没有 dirty app frame 的间隔，不是一个持续 220 ms 的 UI 线程任务。因此：

- 页面级回归同时查看 response/e2e、系统 jank 报告和 UI 线程同步区间；
- 不用“无 frame 的等待间隔”冒充 C++ 节点构建耗时；
- 也不因此忽略外层布局真实存在的 30 ms 级峰值。

## 兼容与回退

- 当前 native UI 库仅构建 `arm64-v8a`。项目已有的 EasyTier Core HAR 同样仅包含 arm64，因此没有新增原本可用的 x86 模拟器 ABI 回归。
- 目标 API 保持 `6.1.0(23)`。
- Native 创建失败自动回退 ArkTS 文本；配置数据和交互所有权始终在 ArkTS。
- 同一进程的两次配置页进入共产生 40 次 native create；第一次离开页面恰好产生 20 次 destroy，随后可正常重建。单卡切换只记录 1 次 native update。
- 修改需要在 phone、tablet、2in1 上继续验证；平板三栏是本轮主要性能基准。

## Core/HAR provenance

最终 Core 源码来自 `perf/ohos-config-packages` 的提交 `1a5f17a6`（基于官方 `upstream/main` 的 `4a10d1c2`）：

- `libeasytier_ohrs.so` SHA-256：`b20ace4f77f23155a53d9586e1efaa7abd098491503aca3a5ca19740d2fe0189`
- `easytier-ohrs-0.0.1.har` SHA-256：`58317f843375078062cac1276ec812b450cdc71af58c60cd58351cd830a88b4f`
- Debug HAP 内嵌 Core `.so` SHA-256：`988c6914c0215dce984744f76ddfd5e73a75c43d548a4f7d64e3e26973acde61`。Hvigor 只移除了输入 ELF 的 `.comment` section，其余 loadable sections 与动态符号保持一致。
- 动态符号中只有一个 `napi_register_module_v1`；内层 Features/Kernel crate 不含 N-API 注册或依赖。
