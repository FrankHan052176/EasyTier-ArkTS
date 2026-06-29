# EasyTier for HarmonyOS NEXT

> 基于 HarmonyOS 原生壳工程 + EasyTier Rust 内核 HAR 的跨端组网客户端

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-6.0.2%20(API%2022)-8A2BE2)](https://developer.harmonyos.com)
[![ArkTS](https://img.shields.io/badge/ArkTS-Native-blue)](https://developer.harmonyos.com)
[![EasyTier Core](https://img.shields.io/badge/EasyTier-Rust%20HAR-green)](https://github.com/EasyTier/EasyTier)
[![License](https://img.shields.io/badge/License-AGPL--3.0-yellow)](#许可证)

## 📖 项目简介

本项目采用 **HarmonyOS 原生壳工程 + EasyTier Rust 内核 HAR** 的混合架构：

- **HarmonyOS 壳工程**：使用 ArkTS、ArkUI、HMRouter 和 HarmonyOS Extension Ability 构建完整客户端界面，负责配置管理、状态展示、系统权限、后台任务、分享、云同步、远端控制和桌面组件等系统集成能力
- **EasyTier 内核层**：通过 `easytier-ohrs` HAR 集成 Rust 原生网络核心，提供 EasyTier 组网、VPN 隧道、运行状态、日志与配置桥接能力
- **系统网络能力**：通过 `VpnExtensionAbility` 接入系统 VPN 框架，并结合后台任务、通知、状态栏视图和权限管理，让组网服务可以在鸿蒙设备上稳定运行

这种架构让 EasyTier 的高性能 Rust 内核能够以原生 HAR 形式嵌入鸿蒙应用，同时让 UI、权限、文件、分享、云同步和设备适配完全走 HarmonyOS 原生能力。

## 🏗️ 项目结构

```bash
EasyTier/
│
├── AppScope/                         # 应用级配置（包名、图标、版本、云同步）
│   ├── app.json5                     # 应用元信息（bundleName = top.frankhan.easytier）
│   └── resources/
│       └── base/
│           ├── element/              # 应用级字符串资源
│           └── media/                # 应用图标、分层图标、启动图
│
├── entry/                            # 鸿蒙模块：EasyTier 客户端入口
│   ├── src/main/ets/
│   │   ├── AppManager.ets            # 全局应用状态和服务聚合入口
│   │   ├── ConfigSyncUtil.ets        # 配置同步和分享链接处理
│   │   ├── EasyTierUtil.ets          # EasyTier 内核桥接与运行控制
│   │   ├── ToastUtil.ets             # 系统 Toast 封装
│   │   ├── WindowUtil.ets            # 窗口尺寸和布局工具
│   │   │
│   │   ├── entryability/             # Ability 与系统扩展入口
│   │   │   ├── EntryAbility.ets      # 主 UIAbility，应用启动与生命周期
│   │   │   ├── EasyTierAbility.ets   # VPN Extension Ability
│   │   │   ├── EntryFormAbility.ets  # 桌面卡片 Ability
│   │   │   └── StatusBarViewAbility.ets # 状态栏视图 Ability
│   │   │
│   │   ├── entrybackupability/
│   │   │   └── EntryBackupAbility.ets # 备份恢复扩展
│   │   │
│   │   ├── pages/                    # 页面入口
│   │   │   ├── HMRouterIndex.ets     # HMRouter 根页面
│   │   │   ├── StatusBarPage.ets     # 状态栏视图页面
│   │   │   └── hmrouter/
│   │   │       ├── HomePage.ets      # 首页
│   │   │       ├── EditPage.ets      # 配置编辑页
│   │   │       ├── StatusPage.ets    # 本机运行状态页
│   │   │       ├── HelpPage.ets      # 帮助页
│   │   │       ├── RemoteControlPage.ets # 跨端控制入口
│   │   │       ├── RemoteSettingPage.ets # 远端设置页
│   │   │       ├── RemoteStatusPage.ets  # 远端状态页
│   │   │       └── remote/
│   │   │           └── RemoteSummaryViewState.ets
│   │   │
│   │   ├── components/               # ArkUI 组件
│   │   │   ├── index/                # 首页卡片、日志、实例、收藏等组件
│   │   │   ├── sheet/                # 设置页、弹窗和底部面板
│   │   │   ├── edit/                 # 半配置化编辑器
│   │   │   ├── status/               # 状态展示组件
│   │   │   ├── util/                 # 通用按钮、选择器、二维码等组件
│   │   │   └── widgets/              # 桌面卡片页面
│   │   │
│   │   ├── config/                   # 配置渲染和字段 Schema
│   │   │   ├── defaults/             # 默认配置
│   │   │   ├── fields/               # 字段注册与 UI 定义
│   │   │   ├── render/               # 配置编辑渲染计划
│   │   │   └── schema/               # Schema 布局与模型
│   │   │
│   │   ├── infrastructure/bridge/kernel/
│   │   │   ├── KernelBridgeTypes.ets # 内核桥接类型
│   │   │   ├── RouteStore.ets        # 路由/网络状态缓存
│   │   │   ├── SocketCodec.ets       # Socket 数据编解码
│   │   │   └── VpnExtensionSocketBridge.ets
│   │   │
│   │   ├── services/                 # 业务服务层
│   │   │   ├── cloud/                # 云空间同步
│   │   │   ├── config/storage/       # 配置持久化
│   │   │   ├── crash/                # 崩溃日志
│   │   │   ├── data/storage/         # 数据迁移与存储
│   │   │   ├── easytier/runtime/     # EasyTier 启停编排
│   │   │   ├── form/                 # 桌面卡片通信
│   │   │   ├── permission/           # 权限检测与申请
│   │   │   ├── preferences/storage/  # Preferences 封装
│   │   │   ├── remote/               # 跨端控制服务
│   │   │   └── runtime/              # 运行时长与内存统计
│   │   │
│   │   ├── store/                    # UI 状态
│   │   ├── types/                    # 类型定义
│   │   └── util/                     # 分享、事件、信息、转换工具
│   │
│   ├── src/main/resources/           # 模块资源
│   │   ├── base/
│   │   │   ├── element/              # 字符串、颜色、资源定义
│   │   │   ├── media/                # 图片与图标
│   │   │   └── profile/              # 路由、权限、备份、卡片配置
│   │   ├── dark/element/             # 深色模式资源
│   │   ├── rawfile/                  # 原始资源
│   │   └── zh/element/               # 中文资源
│   │
│   ├── build-profile.json5           # 模块构建配置
│   ├── hvigorfile.ts                 # 模块构建脚本
│   ├── obfuscation-rules.txt         # 混淆规则
│   └── oh-package.json5              # 模块依赖配置
│
├── easytier-ohrs-0.0.1.har           # EasyTier Rust 内核 HAR（项目内本地依赖）
├── hmrouter_config.json              # HMRouter 插件配置
├── signing/                          # 签名配置和材料
├── hvigor/                           # Hvigor 配置
│   └── hvigor-config.json5
├── build-profile.json5               # 应用产品、SDK 和模块定义
├── hvigorfile.ts                     # 应用构建脚本入口
├── oh-package.json5                  # 项目级 ohpm 依赖
└── README.md
```

## ✨ 核心功能

| 功能 | 说明 |
|------|------|
| 🔗 **EasyTier 组网** | 通过 Rust 内核 HAR 启动 EasyTier 网络实例 |
| 🛡️ **系统 VPN 隧道** | 使用 `VpnExtensionAbility` 接入 HarmonyOS VPN 框架 |
| 🧩 **多实例配置管理** | 支持创建、编辑、收藏、重命名和删除多个网络配置 |
| 📥 **配置导入** | 支持分享链接、文件、剪贴板和二维码导入 |
| 📤 **配置导出** | 支持系统分享面板、二维码和配置链接导出 |
| 📊 **运行状态** | 展示虚拟 IP、NAT 类型、TUN 状态、节点信息和运行实例 |
| 🧠 **半配置化编辑器** | 通过 Schema 和字段注册表动态渲染复杂配置项 |
| ☁️ **云空间同步** | 支持配置缓存、上传、下载和同步状态显示 |
| 🖥️ **可重构首页布局** | 首页卡片可拖拽、调整位置和尺寸，适配手机、平板与 2in1 |
| 🧭 **跨端控制** | 管理远端设备的配置、运行状态和基础设置 |
| 🧾 **日志与调试** | 支持内核日志、调试日志、崩溃日志分享和运行统计 |
| 📌 **状态栏视图** | 通过 `StatusBarViewExtensionAbility` 展示轻量连接状态 |
| 🪟 **桌面卡片** | 通过 Form Ability 提供桌面快捷入口和状态展示 |
| 🤲 **握持姿态适配** | 结合手势检测调整关键交互位置，优化单手操作 |
| 🎨 **HDS 原生视觉** | 使用 HDS Navigation、系统符号、动效和鸿蒙资源体系 |

## 🧭 功能适配情况

> 这里的“未落地”并不是“想做却没做成”，而是基于当前 HarmonyOS 客户端定位、系统能力边界与安全策略做出的主动裁剪。当前版本重点保障“稳定组网、易于配置、可持续运行”，避免把桌面端所有高级网络能力盲目移植到移动端。

| 能力 | 状态 | 说明 |
|------|------|------|
| EasyTier 基础组网 | ✅ 已支持 | 可通过内核 HAR 启动 EasyTier 实例，建立节点与隧道连接 |
| 系统 VPN 隧道接入 | ✅ 已支持 | 通过 `VpnExtensionAbility` 接入 HarmonyOS VPN 框架 |
| 多实例配置管理 | ✅ 已支持 | 支持创建、编辑、收藏、重命名和删除多个网络配置 |
| 配置导入/导出 | ✅ 已支持 | 支持分享链接、文件、剪贴板和二维码导入导出 |
| 运行状态与日志 | ✅ 已支持 | 展示虚拟 IP、NAT 类型、TUN 状态、节点信息与运行日志 |
| 后台运行与通知 | ✅ 已支持 | 支持后台任务、通知提醒和状态栏轻量展示 |
| 云同步与跨端能力入口 | ✅ 已支持 | 提供配置缓存、上传下载和跨端控制入口 |
| 高级路由策略与深度系统控制 | ⚠️ 部分支持 | 目前已支持常见的组网场景；其中 `faketcp` 因 `raw socket` 权限限制无法落地，`ping` 代理因 `icmp socket` 权限限制无法落地 |
| Web 控制台接入 | ❌ 未适配 | 当前版本暂不适配 Web 控制台，原因是 HarmonyOS 端当前只能启动一个 TUN，且实例共享 TUN 的能力在上游主线尚未落地 |

## 🧱 T0 / T1 / T2 功能分级说明

本项目的适配能力按“可用性、日常使用体验与平台增强”三层进行分级，目标是先把最核心的组网流程做稳，再逐步补齐更丰富的体验能力。

### T0 基础能力（组网主流程）

| 能力 | 状态 | 说明 |
|------|------|------|
| HAP 构建与安装 | ✅ 已支持 | 可通过 Hvigor / DevEco 构建并安装 HAP 包 |
| 应用启动与主界面 | ✅ 已支持 | 安装后可正常启动并进入配置与状态主界面 |
| 配置创建与导入 | ✅ 已支持 | 支持手动创建、分享链接、文件、剪贴板和二维码导入 |
| EasyTier 实例启动 | ✅ 已支持 | 可启动组网实例并建立基础隧道连接 |
| 运行状态展示 | ✅ 已支持 | 展示节点、虚拟 IP、TUN、NAT 等基础状态，且可观测关键运行信息 |

小结：T0 这一层聚焦“能用”的基础组网流程，当前项目已经覆盖应用可构建、配置可落地、实例可启动与状态可观测。

### T1 核心能力（日常组网）

| 能力 | 状态 | 说明 |
|------|------|------|
| 多实例管理 | ✅ 已支持 | 支持多配置并存、收藏、重命名和删除 |
| 配置导出与分享 | ✅ 已支持 | 支持系统分享、二维码和链接导出 |
| 日志与调试信息 | ✅ 已支持 | 提供内核日志、调试日志和运行统计信息 |
| 后台运行与通知 | ✅ 已支持 | 保持组网服务可持续运行，并提供状态提醒 |
| 高级协议能力 | ⚠️ 部分支持 | 目前已覆盖常见组网场景；其中 `faketcp` 与 `ping` 代理因系统权限限制暂不可用 |

小结：T1 层覆盖日常组网的核心使用场景，当前项目已实现较完整的配置、运维与可观测体验。

### T2 增强能力（平台体验与安全取舍）

| 能能 | 状态 | 说明 |
|------|------|------|
| HarmonyOS 原生视觉与交互 | ✅ 已支持 | 采用 ArkTS、ArkUI、HDS 视觉体系与系统原生交互 |
| 桌面卡片与状态栏入口 | ✅ 已支持 | 提供桌面快捷入口和轻量状态展示 |
| 可重构首页布局 | ✅ 已支持 | 首页卡片支持拖拽、调整位置和尺寸 |
| 手势与握持姿态适配 | ✅ 已支持 | 针对单手操作和横竖屏场景进行体验优化 |
| 云同步与跨端入口 | ✅ 已支持 | 支持配置同步、缓存上传下载和远端控制入口 |
| Web 控制台接入 | ❌ 未适配 | 由于当前 HarmonyOS 端只能启动一个 TUN，且实例共享 TUN 能力在上游主线尚未落地，暂不进行适配 |
| 复杂系统级控制能力 | ❌ 未落地 | 当前不提供被控端部署、侵入式路由控制或高风险扩展能力 |

小结：T2 层强调平台体验与安全取舍，项目当前已实现较好的 HarmonyOS 原生体验，同时主动回避高风险、易滥用的系统能力。

## 🚀 构建与运行

### 环境要求

| 工具 | 版本 |
|------|------|
| DevEco Studio | 建议使用当前最新版 |
| HarmonyOS SDK | target `6.0.2(22)`，compatible `6.0.0(20)` |
| ohpm / hvigor | 使用 DevEco Studio 随附版本 |
| Node.js | 使用 DevEco/Hvigor 环境要求版本 |
| EasyTier 内核 HAR | `easytier-ohrs-0.0.1.har` |

### 安装依赖

```bash
cd EasyTier
ohpm install
```

当前项目级依赖中，EasyTier 内核使用项目内本地 HAR：

```json5
"easytier-ohrs": "file:./easytier-ohrs-0.0.1.har"
```

### 构建 HAP 包

```bash
# 在 EasyTier 工程根目录执行
hvigorw --mode module -p module=entry@default assembleHap

# 产物路径
entry/build/default/outputs/default/entry-default-signed.hap
```

也可以在 DevEco Studio 中打开 `EasyTier/` 目录，然后执行：

```text
Build → Build Hap(s)/APP(s) → Build Hap(s)
```

### 真机测试

1. 连接 HarmonyOS NEXT 设备或启动模拟器
2. 在 DevEco Studio 中选择 `entry` 模块运行，或使用命令安装 HAP
3. 首次启动时按系统提示授予 VPN、通知、位置、分布式数据同步等必要权限
4. 创建或导入 EasyTier 配置后启动组网

```bash
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

> ⚠️ 首次运行需要确保签名配置正确。VPN 功能会触发系统授权弹窗，用户确认后才能建立隧道。

## 🧩 EasyTier 内核 HAR 开发说明

### 内核来源

鸿蒙壳工程通过 `easytier-ohrs` HAR 集成 Rust 内核。当前壳工程内使用的 HAR 文件为：

```bash
EasyTier/easytier-ohrs-0.0.1.har
```

上游内核工程通常位于同级目录：

```bash
../EasyTier-Core/easytier-contrib/easytier-ohrs/
```

### 核心文件说明

```bash
EasyTier-Core/easytier-contrib/easytier-ohrs/
├── Cargo.toml                  # Rust crate 配置
├── build.rs                    # Rust 构建脚本
├── src/
│   ├── lib.rs                  # Rust NAPI 模块入口
│   ├── exports.rs              # 导出接口
│   ├── runtime.rs              # EasyTier 运行时控制
│   ├── config.rs               # 配置结构与转换
│   ├── config_repo.rs          # 配置仓库逻辑
│   ├── kernel_bridge.rs        # 内核桥接
│   └── platform.rs             # 平台相关适配
├── dist/
│   └── index.d.ts              # TypeScript 类型声明
├── package/
│   ├── index.ets               # HAR ArkTS 入口
│   ├── oh-package.json5        # HAR 包元信息（name = easytier-ohrs）
│   └── src/main/module.json5   # HAR 模块配置
└── package.har                 # 构建得到的 HAR 产物
```

### 更新 HAR 到鸿蒙壳

当 `EasyTier-Core` 中重新构建了 `package.har` 后，将其复制进鸿蒙壳目录，并重新安装依赖：

```bash
cd ..
cp EasyTier-Core/easytier-contrib/easytier-ohrs/package.har EasyTier/easytier-ohrs-0.0.1.har

cd EasyTier
ohpm install
hvigorw --mode module -p module=entry@default assembleHap
```

### 壳工程开发流程

1. **修改 ArkTS 代码**：主要在 `entry/src/main/ets/` 下开发 UI、服务和 Ability
2. **更新内核 HAR**：如 Rust 内核接口变化，先更新 `easytier-ohrs-0.0.1.har`，再执行 `ohpm install`
3. **重新构建**：执行 `hvigorw --mode module -p module=entry@default assembleHap`
4. **真机验证**：安装 HAP 后重点验证 VPN 授权、组网启动、日志、状态页和配置导入导出

## 📄 许可证

本项目基于 **AGPL-3.0 License** 开源。EasyTier 内核和相关依赖遵循各自上游许可证。
