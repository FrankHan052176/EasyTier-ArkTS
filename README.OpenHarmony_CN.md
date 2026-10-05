# EasyTier 的鸿蒙 PC / OpenHarmony 适配说明

本文说明开源 EasyTier 如何在鸿蒙 PC（2in1）工程中编译、安装和运行，以及 PC 适配涉及哪些代码。当前应用构建目标是 **HarmonyOS 6.1.0（API 23）**，使用 HarmonyOS 原生 ArkTS / ArkUI 与 EasyTier Rust HAR，不是把 Windows/Linux 桌面二进制直接搬到 PC 上。

文件沿用社区要求的 `README.OpenHarmony_CN.md` 名称；工程实际依赖 HarmonyOS SDK 与部分华为平台服务。不能据此承诺在任意纯 OpenHarmony 镜像中直接构建或运行。

- 社区应用仓库：https://atomgit.com/OpenHarmonyPCDeveloper/ohos_easytier
- Rust 内核适配仓库：https://atomgit.com/FrankHan2004/EasyTier
- EasyTier 上游：https://github.com/EasyTier/EasyTier
- 迁移能力与 T0/T1/T2 分级：[README.md](README.md) 的“鸿蒙 PC 迁移阶段与能力边界”一节

## 一、移植方案与工程边界

```text
ArkTS / ArkUI 应用
  配置界面、窗口布局、权限与系统 VPN/TUN 衔接
             │ NAPI
             ▼
easytier-ohrs HAR
  ArkTS 入口、类型声明、arm64 Native 库
             │
             ▼
EasyTier Rust 内核
  实例、节点连接、协议、路由与数据转发
```

系统侧创建 TUN 后将 fd 注入 Rust；本地内核 socket 提供拓扑、流量统计和 TUN 请求，不承担把业务数据包送到 ArkTS 页面再转发的工作。主进程与 VPN 扩展进程是不同的运行宿主路径，具体由应用运行模式决定，不应把 `VpnExtensionAbility` 声明等同于所有构建都使用扩展进程。

仓库根目录就是 DevEco 工程，入口模块为 `entry`。主要文件如下：

| 路径 | 用途 |
| --- | --- |
| `AppScope/app.json5` | 包名 `top.frankhan.easytier` 及应用版本 |
| `build-profile.json5` | `default` / `publish` 产品及 SDK 配置 |
| `hvigorfile.ts` | HMRouter 插件、构建信息与外部签名注入 |
| `oh-package.json5` | 包依赖，Core 使用仓库携带的本地 HAR |
| `entry/src/main/module.json5` | `2in1` 设备、窗口模式、Ability 与权限 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 入口、窗口尺寸监听与运行宿主衔接 |
| `entry/src/main/ets/WindowUtil.ets` | 窗口尺寸与一、二、三栏布局状态 |
| `entry/src/main/ets/pages/hmrouter/EditPage.ets` | 配置页可见分区与大屏渲染 |
| `entry/src/main/cpp/` | BoolField 文本子树的 Native Node 实现 |

## 二、环境与依赖

| 项目 | 当前工程要求 |
| --- | --- |
| SDK | `targetSdkVersion` 与 `compatibleSdkVersion` 均为 `6.1.0(23)`，以 checkout 的配置为准 |
| 构建工具 | 支持该 SDK 的 DevEco Studio 或 HarmonyOS command-line-tools；使用其配套 Node.js、OHPM、Hvigor |
| 设备 | 支持当前 SDK 的 arm64 鸿蒙 PC / 2in1；不要把 tablet 或手机测试替代成 PC 桌面验收 |
| Native ABI | `arm64-v8a`；已携带 HAR 也只有此架构的 `.so` |
| 签名 | 与当前 bundle 和设备匹配的开发者签名，放在工程外部 |
| Rust 工具链 | 仅在重建 Core HAR 时需要；只编译应用无需先装 Rust 或重建 Core |

仓库已经包含 `easytier-ohrs-0.0.1.har`，`oh-package.json5` 将其作为 `file:./easytier-ohrs-0.0.1.har` 依赖。它是 gzip tar 归档，包含 `package/libs/arm64-v8a/libeasytier_ohrs.so`、类型声明和 ArkTS 入口，不能用 `unzip` 失败来判断 HAR 损坏。

```bash
git clone https://atomgit.com/OpenHarmonyPCDeveloper/ohos_easytier.git
cd ohos_easytier

# 将 CLI_HOME 指向已解压的 command-line-tools 根目录。
export CLI_HOME="$HOME/command-line-tools"
export PATH="$CLI_HOME/bin:$PATH"
export SDK_ROOT="$CLI_HOME/sdk/default/openharmony"
export HDC="$SDK_ROOT/toolchains/hdc"

hvigorw --version
ohpm --version
ohpm install
```

仓库不自带 `hvigorw` 文件，上述命令使用 command-line-tools 的 `bin/hvigorw`。若通过 DevEco Studio 构建，用其配套工具，不要混用另一套 Node.js/SDK。构建脚本还会获取上游的配置字段翻译资源，因此环境需要能访问所配置的下载地址；下载异常应按真实构建日志处理。

## 三、签名准备

签名材料不得提交进仓库。当前 `hvigorfile.ts` 从 `EASYTIER_SIGNING_DIR/signingConfigs.json` 读取 JSON 数组，并要求其中同时包含名为 `default` 和 `publish` 的条目；构建时按产品名注入。

1. 使用自己的开发者账号，在 DevEco / 开发者平台为 `top.frankhan.easytier` 准备匹配的证书与 profile，调试 profile 覆盖目标 PC 设备。
2. 根据 DevEco 的签名配置，将证书、profile、keystore 路径和密码配置整理到工程外部的 `signingConfigs.json`。这些都是个人私密配置，不能复制项目维护者的材料或使用无效示例替代。
3. 将 `EASYTIER_SIGNING_DIR` 设置为该配置所在目录，并导出给 Hvigor：

```bash
# 指向你自己保存签名配置的目录，先在当前 shell 中设置该变量。
: "${EASYTIER_SIGNING_DIR:?请先设置工程外部的签名目录}"
export EASYTIER_SIGNING_DIR
```

仅构建 Debug 时也需满足当前脚本的两个条目检查。未设置变量时脚本不注入签名；不能因此把无签名产物当作已签名真机包。若在 DevEco 使用自己的签名配置，也必须检查最终 product 绑定与 bundle/设备是否匹配。

## 四、构建与产物检查

### 本地 Debug

在仓库根执行：

```bash
hvigorw assembleApp \
  --mode project \
  -p product=default \
  -p buildMode=debug \
  --no-daemon
```

预期安装用 HAP：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

也可以在 DevEco Studio 打开仓库根目录，选择 `entry`、`default` 产品和 Debug 模式，配置好自己的签名后构建或 Run。

本地 Debug 版本保留 `AppScope/app.json5` 的 `0.0.1 / 99999999`。安装前检查 HAP 元数据，不只看文件名：

```bash
export HAP="entry/build/default/outputs/default/entry-default-signed.hap"
unzip -p "$HAP" module.json
unzip -l "$HAP"
```

检查 `buildMode=debug`、`debug=true`、bundleName、版本，以及 `libs/arm64-v8a/` 下的 Native 库。`module.json` 中的版本应与本地 checkout 对应；CI 发布流程可以改写版本，不能用其版本规则解释本地 Debug。

### 发布包

发布使用自己的发布签名和 `publish/release`，与 Debug 是另一条路径：

```bash
hvigorw assembleApp \
  --mode project \
  -p product=publish \
  -p buildMode=release \
  --no-daemon
```

生成 App 包不代表已在商店上架。开发测试分发与正式商店版本分别处理，具体流程见 [docs/AGC_API_CI.md](docs/AGC_API_CI.md) 和 [docs/CHANGELOG_POLICY.md](docs/CHANGELOG_POLICY.md)。不要把 `product=publish` 的包当作本机 Debug 包。

## 五、在鸿蒙 PC 安装与运行

先连接并授权目标 PC，列出设备。随后把 `PC_TARGET` 设为列表中对应 PC 的字面 target id；不要对多个设备广播。

```bash
"$HDC" list targets
: "${PC_TARGET:?请先设置已连接并授权的鸿蒙 PC target id}"

# 先保存旧包信息，再决定覆盖安装还是处理签名冲突。
"$HDC" -t "$PC_TARGET" shell bm dump -n top.frankhan.easytier
"$HDC" -t "$PC_TARGET" install -g "$HAP"
"$HDC" -t "$PC_TARGET" shell aa start \
  -a EntryAbility -b top.frankhan.easytier
"$HDC" -t "$PC_TARGET" shell bm dump -n top.frankhan.easytier
"$HDC" -t "$PC_TARGET" shell pidof top.frankhan.easytier
```

必须检查 HDC 的字面安装成功输出和启动结果，再核对 `bm dump` 中的 bundle、版本、`appIdentifier`、签名 fingerprint 与进程。部分 HDC 失败仍可能返回零退出码，不能只看 shell 状态。

若已有商店/测试包与本地 Debug 证书不同，不能跨证书强行覆盖。要保留数据，先处理同签名更新或数据迁移；若接受清空应用数据，可明确卸载后再安装自己的 Debug 包。卸载会清除该 bundle 的本地数据，不要把它写成每次安装必做的步骤。

首次启用组网，按系统提示确认 VPN 授权；通知、同步、扫码等权限按使用的功能申请。创建或导入一份你有权使用的组网配置，启动后观察 TUN、Peer 和日志，再从对端验证虚拟网络访问。应用能启动、实例运行、TUN 挂载、Peer 建连和目标服务可访问，是不同的验收结果。

## 六、PC 适配具体完成了什么

### 窗口与大屏布局

`entry/src/main/module.json5` 声明 `2in1`，`EntryAbility` 支持 `floating`、`split`、`fullscreen`。`windowSizeChange` 会调用 `WindowUtil.update()`，先将像素转换为 vp，再按窗口宽度选择布局：

| 窗口宽度 | 布局 |
| --- | --- |
| 小于 720 vp | 单栏 |
| 720 vp 至小于 1080 vp | 双栏 |
| 不小于 1080 vp | 三栏 |

配置页据此设置可见分区数量，首页使用可调整的卡片布局；不是把某个手机截图拉伸成 PC 页面。桌面验收需要调整实际窗口大小，检查窄窗口入口、宽窗口多栏和浮窗操作。工程中模拟器专用的窄窗口分支不能代表 PC 真机宽窗口行为。

### 页面加载与 Native 文本子树

配置编辑分区、行和递归分组共用全页逐帧队列，避免各组件同时加载造成总量叠加。BoolField 的两段文字使用 ArkUI Native Node，容器、图标、交互与数据仍由 ArkTS 管理，创建失败回退到 ArkTS。

既有真机性能记录见 [docs/CONFIG_PAGE_PERFORMANCE.md](docs/CONFIG_PAGE_PERFORMANCE.md)。其 A/B 数字有设备、字段数量和 Debug 构建条件，不能直接换算成整个应用的速度提升。

### 网络与平台边界

- TUN 由系统创建，Rust 接收 fd；不能直接照搬普通 Linux 的设备创建和系统路由配置。
- 内核选定的 socket 经 `VpnConnection.protect()` 保护，等待异步确认后再继续网络操作。
- `completeSocketProtection()` 返回值表示结果是否被接收，不等于 `protect()` 是否成功。已取消请求的确认可能返回 `false`，不能因此把其他正常实例停掉；停止时仍需等待在途操作完成并回传确认。
- 多配置持久化不代表多个实例能够分别创建独立系统 TUN。
- `faketcp`、ICMP `ping` 代理等高权限路径并非当前支持能力；Web 控制台没有按上游桌面多实例方式接入。
- 运行保持、状态栏、卡片、云同步和跨设备入口受设备能力、权限、账户及网络环境约束，不承诺任意环境永久常驻或全部平台能力等价。

## 七、可选：更新 Rust HAR

只有修改内核或 NAPI 接口时才需要此步骤。进入所选 Core 修订的 `easytier-contrib/easytier-ohrs/`，按该修订的 `env.sh`、Cargo 配置和 ohos-rs 流程构建 arm64 release HAR，再一起更新 Native 库、类型声明和包入口。不要只复制 `.so`。

本应用的保护接口应与 Core 修订匹配。更新前先核对生成的声明是否包含应用实际调用的接口；不能把缺接口的旧 HAR 仅改名后装进工程。构建完成后将产物放回应用根的 `easytier-ohrs-0.0.1.har` 并重新 `ohpm install`。

检查 HAR 架构和校验值：

```bash
tar -tzf easytier-ohrs-0.0.1.har
shasum -a 256 easytier-ohrs-0.0.1.har
```

只处理 OHRS 时，不在 Core 根目录跑无包范围的 Cargo 全工作区构建；Host Debug 的 `cargo check` 也不能替代 HarmonyOS arm64 release 交叉编译与包内 `.so` 校验。

## 八、完整 PC 截图与验收清单

![EasyTier 在鸿蒙 PC 桌面运行，保留完整任务栏与应用窗口](docs/images/harmonyos-pc-runtime.jpeg)

已有测试截图，原始分辨率 3120×2080，未裁剪或拼接。它展示应用在 PC 桌面启动并窗口化运行；图中实例未启动，因此不是节点互通、切网或后台稳定性的证明，也不是本次文档更新新采集的截图。

按 README 的 T0/T1/T2 分阶段检查：

- **T0**：构建与签名元数据正确，字面安装成功，启动进程存在，PC 主界面可见，配置有效；再单独验证系统授权、TUN 挂载与节点互通。
- **T1**：配置导入导出一致、正常停止清理、连续启停不交错、网络切换后状态恢复、日志可解释故障。
- **T2**：保留桌面与任务栏的全屏截图，浮窗/分屏/最大化尺寸变化后布局正确，鼠标操作与宽屏配置页加载可用，平台入口按设备能力展示。

本说明更新核对了工程配置、HAR 归档与已有截图，未在本轮重新构建签名 HAP 或完成 PC 全功能回归。历史截图不替代当前源码每个能力的真机验收；提交评审时应把构建记录、包信息、运行截图与组网测试分别保留。
