# RustDesk 接入 EasyTier 三方预组网 API v1

本文是 EasyTier-ArkTS 当前实现的调用方契约。RustDesk 应严格按本文常量和状态机接入，不要继续使用此前在 RustDesk 侧自行假设的 URI、action 或载荷。

官方机制依据：

- [跨应用数据共享](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/cross-app-data-share)
- [应用间配置共享（ArkTS）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/share-config)
- [DataShare API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-data-datashare)
- [Want](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-want)
- [UIAbility](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-uiability)

## 1. 已实现的 EasyTier 能力

EasyTier 作为受控 API 提供方，当前支持三个操作：

| operation | 含义 | 是否改变运行状态 |
| --- | --- | --- |
| `list_instances` | 返回最多 10 个已保存实例的 ID、显示名和运行状态 | 否 |
| `query_instance` | 查询一个指定实例的当前运行状态 | 否 |
| `ensure_instance_running` | 若指定实例未运行，则停止现有实例、启动指定实例，并等待内核真实运行快照 | 是 |

`ensure_instance_running` 只有在 EasyTier 内核真实运行快照确认后才返回成功。仅进入启动队列、VPN Extension 接受请求或 UI 乐观状态都不算成功。

实现位置：

- `entry/src/main/ets/services/integration/ThirdPartyApiContract.ets`
- `entry/src/main/ets/services/integration/ThirdPartyApiService.ets`
- `entry/src/main/ets/entryability/EntryAbility.ets`
- `entry/src/main/ets/EasyTierUtil.ets`
- `entry/src/main/resources/base/profile/third_party_shared_config.json`
- `entry/src/main/module.json5`

## 2. 固定身份与地址

### EasyTier 提供方

| 项目 | 值 |
| --- | --- |
| bundleName | `top.frankhan.easytier` |
| appIdentifier | `6917581172490635834` |
| moduleName | `entry` |
| abilityName | `EntryAbility` |

### RustDesk 调用方

| 项目 | 值 |
| --- | --- |
| bundleName | `top.frankhan.resk` |
| appIdentifier | `6917605780518421882` |
| moduleName | `entry` |
| abilityName | `EntryAbility` |

### 协议常量

| 项目 | 值 |
| --- | --- |
| schemaVersion | `1` |
| 请求 action | `top.frankhan.easytier.action.THIRD_PARTY_API_REQUEST` |
| 结果 action | `top.frankhan.easytier.action.THIRD_PARTY_API_RESULT` |
| requestId 参数键 | `top.frankhan.easytier.api.requestId` |
| operation 参数键 | `top.frankhan.easytier.api.operation` |
| RustDesk 请求 URI | `datashareproxy://top.frankhan.resk/easytier_api/v1/request` |
| EasyTier 能力 URI | `datashareproxy://top.frankhan.easytier/third_party_api/v1/capabilities/rustdesk` |
| EasyTier 结果 URI | `datashareproxy://top.frankhan.easytier/third_party_api/v1/result/rustdesk` |

EasyTier 的能力与结果 URI 已通过 `crossAppSharedConfig` 静态注册，并只允许 RustDesk 的 appIdentifier 读取。升级 EasyTier 后需要确保系统重新安装/更新 HAP，使静态共享配置完成注册。

## 3. RustDesk 必须增加的静态共享配置

RustDesk 是请求发布方，需要在 `entry/src/main/module.json5` 的 `module` 节点增加：

```json5
"crossAppSharedConfig": "$profile:easytier_api_shared_config"
```

新增 `entry/src/main/resources/base/profile/easytier_api_shared_config.json`：

```json
{
  "crossAppSharedConfig": [
    {
      "uri": "datashareproxy://top.frankhan.resk/easytier_api/v1/request",
      "value": "{\"schemaVersion\":1,\"requestId\":\"\",\"operation\":\"\",\"issuedAt\":0}",
      "allowList": [
        "6917581172490635834"
      ]
    }
  ]
}
```

每次请求时 RustDesk 使用 `DataProxyType.SHARED_CONFIG` 和 `publish()` 覆盖这个固定请求 URI，`allowList` 必须仍为 EasyTier 的 appIdentifier。不要为每次请求创建新 URI，以免触发每个应用最多 32 个共享配置项的限制。

## 4. 请求载荷

### `list_instances`

```json
{
  "schemaVersion": 1,
  "requestId": "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx",
  "operation": "list_instances",
  "issuedAt": 1785600000000
}
```

### `query_instance` / `ensure_instance_running`

```json
{
  "schemaVersion": 1,
  "requestId": "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx",
  "operation": "ensure_instance_running",
  "issuedAt": 1785600000000,
  "instanceId": "EasyTier 中已保存的 configId"
}
```

规则：

- `requestId` 必须是小写 UUID v4，每次操作使用新值。
- `issuedAt` 是当前 Unix 毫秒时间戳。
- 请求有效期为 5 分钟，允许最多 5 秒未来时钟偏差。
- 除 `list_instances` 外，必须提供实例 ID。
- 远控目标、会话类型、密码、网络密钥以及 RustDesk 内部状态都不得写入该载荷。
- RustDesk 应在本地持久化原始连接目标和连接类型，EasyTier 只负责准备组网。

## 5. 发起 Want

RustDesk 发布请求成功后，使用显式 Want 拉起 EasyTier：

```arkts
const want: Want = {
  bundleName: 'top.frankhan.easytier',
  moduleName: 'entry',
  abilityName: 'EntryAbility',
  action: 'top.frankhan.easytier.action.THIRD_PARTY_API_REQUEST',
  uri: 'datashareproxy://top.frankhan.resk/easytier_api/v1/request',
  parameters: {
    'top.frankhan.easytier.api.requestId': requestId
  }
}
await context.startAbility(want)
```

Want 只携带 requestId。EasyTier 从共享配置读取完整请求，并使用系统自动写入、调用方无法伪造的以下字段校验 RustDesk：

- `ohos.aafwk.param.callerBundleName`
- `ohos.aafwk.param.callerAppIdentifier`

RustDesk 不应手动填写这两个系统字段。

## 6. EasyTier 的处理状态机

```text
收到显式 Want
→ 校验 action
→ 校验系统注入的 RustDesk bundleName + appIdentifier
→ 校验 Want.uri 必须是 RustDesk 登记的请求 URI
→ 从 SHARED_CONFIG 读取请求 JSON
→ 校验 schemaVersion / requestId / operation / TTL / instanceId
→ 持久化 requestId 防重放
→ 执行 list/query/ensure
→ 将结果 publish 到 RustDesk 独占结果 URI
→ publish 成功后显式 Want 拉回 RustDesk
```

同一个调用方同一时间只处理一个请求。重复 requestId 会返回 `REPLAYED_REQUEST`。

## 7. 结果载荷

通用结构：

```json
{
  "schemaVersion": 1,
  "requestId": "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx",
  "operation": "ensure_instance_running",
  "issuedAt": 1785600005000,
  "ok": true,
  "code": "OK",
  "message": "EasyTier 实例已启动并由内核确认运行",
  "instance": {
    "instanceId": "config-id",
    "instanceName": "办公网络",
    "state": "running",
    "virtualIpv4": "10.126.126.2",
    "peerCount": 3
  }
}
```

`list_instances` 使用 `instances` 数组，并可能返回 `truncated: true`。为了保持共享配置值小于 4096 字节，当前最多返回 10 个实例。

实例状态：

| state | 含义 |
| --- | --- |
| `stopped` | 没有运行或启动证据 |
| `starting` | 启动请求已接受或只有乐观运行状态，尚未收到内核真实快照 |
| `running` | 已收到内核真实运行快照 |

主要结果码：

| code | 含义 |
| --- | --- |
| `OK` | 操作成功 |
| `INVALID_REQUEST` | Want、请求字段或实例 ID 不合法 |
| `REQUEST_EXPIRED` | 请求超过 5 分钟 |
| `REPLAYED_REQUEST` | requestId 已处理 |
| `BUSY` | RustDesk 已有请求正在处理 |
| `INSTANCE_NOT_FOUND` | EasyTier 中不存在该实例 |
| `START_REJECTED` | EasyTier 或系统未接受启动 |
| `RUNTIME_TIMEOUT` | VPN 授权或内核运行确认超时 |
| `INTERNAL_ERROR` | DataShare 或内部处理失败 |

## 8. RustDesk 接收回调

EasyTier 先发布结果，成功后再发送显式 Want：

```text
bundleName  = top.frankhan.resk
moduleName  = entry
abilityName = EntryAbility
action      = top.frankhan.easytier.action.THIRD_PARTY_API_RESULT
uri         = datashareproxy://top.frankhan.easytier/third_party_api/v1/result/rustdesk
parameters[top.frankhan.easytier.api.requestId] = requestId
parameters[top.frankhan.easytier.api.operation] = operation
```

RustDesk 必须在 `EntryAbility.onCreate()` 和 `EntryAbility.onNewWant()` 走同一个回调处理函数，以同时覆盖冷启动和热启动。

回调处理顺序：

1. 校验 action 和结果 URI。
2. 校验系统注入的调用方身份必须是 EasyTier：
   - bundleName `top.frankhan.easytier`
   - appIdentifier `6917581172490635834`
3. 校验 Want requestId 与 RustDesk 本地待处理请求一致。
4. 用 `DataProxyHandle.get()` 读取 EasyTier 结果 URI。
5. 校验结果 `schemaVersion`、requestId、operation 和时间。
6. 仅在 `ok == true`、`code == "OK"`、实例状态为 `running` 时恢复原始 RustDesk 连接。
7. 成功或失败后都清理 RustDesk 本地 pending 状态。

如果 EasyTier 结果发布成功但 `startAbility()` 拉回 RustDesk 失败，结果仍保留在共享配置中。RustDesk 可在自己的等待超时或重新进入前台时主动 `get()` 同一结果 URI，并仍需校验 requestId。

## 9. RustDesk 连接链路要求

正确流程：

```text
用户在 RustDesk 点击远控 / 仅观看 / 相机 / 文件传输
→ 检查“使用 EasyTier 预组网”开关
→ 未开启：沿用原 RustDesk 连接链路
→ 已开启：本地保存原目标、连接类型和 requestId
→ 当前没有已选 ET 实例：先调用 list_instances，让用户选择并保存 configId
→ 发布 ensure_instance_running 请求并拉起 EasyTier
→ RustDesk 不创建远控会话，进入 waiting_for_easytier
→ EasyTier 确认实例运行后拉回 RustDesk
→ RustDesk 校验结果并恢复原连接目标
→ 才创建 RustDesk 会话
```

任何 EasyTier 失败都必须终止等待并显示真实错误，不得自动绕过预组网直接连接。用户若希望绕过，应显式关闭开关或点击单独的“直接连接”。

## 10. RustDesk 具体改动清单

1. 在 `module.json5` 和 profile 中注册 RustDesk 请求共享配置。
2. 用本文契约替换当前未完成的 `EasyTierPreconnectService.ets` 自拟常量与载荷。
3. 在连接入口统一增加一次预组网门控，覆盖远控、仅观看、相机和文件传输。
4. 在本地 Preferences 保存 pending request；远控目标不得发布给 EasyTier。
5. 在 `EntryAbility.onCreate/onNewWant` 统一处理 EasyTier 回调。
6. 通过 `list_instances` 建立 EasyTier 实例选择项；通过 `query_instance` 刷新状态。
7. 对 requestId、TTL、caller bundle/appIdentifier、URI 和结果状态做完整校验。
8. 移除旧的“从 EasyTier 对端列表发起 RustDesk 远控”方向和旧 `EasyTierHandoffService` 协议。

## 11. 当前验证边界

- EasyTier App 级 Debug 构建、资源处理、`ProcessShareConfig`、ArkTS 编译、HAP/App 打包及签名已通过。
- 静态共享配置已经进入生成的 `module.json`。
- RustDesk 消费端尚未按本契约完成，因此本轮没有进行双 App 冷启动、热启动、VPN 授权和回跳联调。
