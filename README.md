# EasyTier 鸿蒙版：技术特性与 Kit 应用概览

**项目简介**：本项目基于 **HarmonyOS Next** (API 12+) 进行了深度原生适配，利用了鸿蒙系统的多种核心 Kit 和高级特性，以提供高性能、分布式的网络隧道体验。

**项目背景**：本应用为首次正式上架应用市场。在此之前，本项目曾参与过“鸿蒙应用开发激励2025”活动，已确认基础激励和一阶段激励。

## 1. 核心网络与底层架构 (Core Network & Architecture)

*   **Network Kit (网络服务)**
    *   **VpnExtensionAbility**: 项目的核心所在。利用鸿蒙原生的 VPN 扩展能力，在系统层级构建网络隧道，实现流量的高效拦截与转发。
    *   **网络连接管理**: 使用 `connection` 模块实时监测网络状态变化，确保在不同网络环境下（Wi-Fi/蜂窝）隧道的稳定性。
*   **NAPI (ArkTS/C++ 互操作)**
    *   **高性能核心**: 通过 C++/Rust 编写高性能的网络核心逻辑（如 `LockFreeRingBuffer` 环形缓冲区），并通过 NAPI 暴露给 ArkTS 层，保证了数据同步低延迟，与Log快速同步。
*   **Background Tasks Kit (后台任务)**
    *   **长效保活**: 申请了 `KEEP_BACKGROUND_RUNNING` 权限，结合连续任务（Continuous Task）机制，确保 VPN 服务在应用退至后台或设备锁屏后依然能稳定运行，不被系统强制回收。

## 2. 数据管理与分布式 (Data & Distributed)

*   **ArkData (方舟数据管理)**
    *   **Preferences (首选项)**: 作为核心配置存储方案，用于持久化保存所有网络实例配置、全局设置及用户偏好，确保数据的快速读写与持久性。
    *   **DistributedKVStore (分布式数据库)**: 用于兼容旧版本数据的迁移与读取，保障升级过程中的数据平滑过渡。
*   **Protobuf 协议兼容**
    *   引入 Protocol Buffers 统一管理跨端与跨语言（ArkTS/C++）的数据结构定义。通过直接兼容 EasyTier 原版数据协议，实现了高效、强类型的通信序列化，确保了多端数据交互的稳定性与生态一致性。

## 3. UI 交互与设计系统 (UI/UX & Design System)

*   **可重构网格布局 (Resizable Grid Layout)**
    *   实现了一套高度可定制的桌面布局系统。用户可以长按并拖拽首页的组件（如实例列表、日志、收藏等），自由调整其位置和大小，实现了类似系统桌面的个性化交互体验。
*   **半配置化 UI (Semi-Config UI)**
    *   采用配置驱动的 UI 架构 (`ContentUtil`)，通过定义数据结构动态生成设置表单和详情页。这不仅实现了 UI 逻辑与业务数据的解耦，还支持了复杂的网络配置项（如 CIDR、端口转发规则）的动态增删。
*   **高性能渲染**
    *   使用 `NodeController`、`BuilderNode` 和 `FrameNode` 等底层接口进行节点操作，确保了复杂布局下的渲染性能。
*   **Multimodal Awareness Kit (多模态感知)**
    *   **握持姿态适配**: 利用 `Motion` 模块检测用户的握持手势（左手/右手），智能调整操作栏（ActionBar）和关键交互元素的位置，优化单手操作体验。
*   **UIDesign Kit (系统设计规范)**
    *   **HDS 组件库**: 深度集成了 `HdsNavigation`、`HdsActionBar` 和 `EditableTitleBar` 等原生高级组件，确保应用视觉风格与系统高度统一。
    *   **沉浸式动效**: 应用了 `hdsEffect`（如高斯模糊、动态点光源），配合自定义转场动画 (`BottomAnimator`)，为界面提供了符合鸿蒙美学的沉浸式视觉层次。
*   **Desktop Extension Kit (桌面扩展)**
    *   **状态栏视图**: 实现了 `StatusBarViewExtensionAbility`，支持在系统顶部状态栏显示实时的网络连接状态或流量信息，实现“信息外显”。

## 4. 系统集成与生态能力 (System Integration & Ecosystem)

*   **AppLinking Kit (应用链接)**
    *   **配置自动导入**: 支持通过 standards 的 AppLinking 链接直接拉起 EasyTier 应用，并自动解析 URL 参数中的配置信息，实现“一键组网”。
    *   **延迟链接 (Deferred Link)**: 即使在用户尚未安装应用的情况下，也能通过延迟链接技术，在应用安装并首次启动后自动触发配置导入逻辑。
*   **Share Kit (分享服务)**
    *   **原生分享**: 接入 `harmonyShare`，支持通过系统标准面板一键导出配置文件或日志链接，并利用 `UTD (Uniform Type Descriptor)` 确保数据类型识别的准确性。
*   **Ability Kit (程序框架)**
    *   **多端适配**: 适配了手机、折叠屏、平板及 2in1 设备（API 12 路由映射）。
    *   **WantAgent**: 用于创建通知栏快捷操作，通过 `WantAgent` 实现从通知栏快速点击返回应用或执行特定任务。
*   **Basic Services Kit (基础公共服务)**
    *   **Emitter**: 实现跨 Ability/跨组件的事件发布订阅，解耦业务逻辑。
    *   **Zlib**: 对传输的大数据包或日志进行实时压缩，节省流量。
    *   **Pasteboard**: 完美适配系统的剪贴板，支持配置文本的快速导入导出。

---

### 技术优势总结
1.  **纯原生 (Pure Native)**: 抛弃了跨平台框架，直接调用鸿蒙底层 API，响应极速。
2.  **高度定制 (Customizable)**: 独创的可重构网格布局与半配置化 UI，提供了极高的界面自由度。
3.  **智能感知 (Intelligent)**: 融合握持检测等多模态交互，提供更懂用户的操作体验。
4.  **分布式与安全**: 充分发挥鸿蒙分布式特性，并严格遵循系统安全与权限模型。
