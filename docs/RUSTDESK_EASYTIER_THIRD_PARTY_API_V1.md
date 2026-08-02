# RustDesk 接入 EasyTier 三方启动 API v2

本文是 EasyTier-ArkTS 当前实现的调用方契约。v2 将“只读状态”和“有副作用命令”分离：RustDesk 通过一个固定 `SHARED_CONFIG` URI 读取并订阅实例快照；只有确实需要启动所选实例时，才发布 `start_instance` 请求并用显式 Want 拉起 EasyTier。

官方机制依据：

- [应用间配置共享（ArkTS）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/share-config)
- [DataShare API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-data-datashare)
- [Want](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-want)
- [UIAbility](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-uiability)

## 1. v2 的核心规则

1. 实例列表、运行状态、虚拟 IPv4 和对端数来自 EasyTier 主动发布的实时快照。
2. RustDesk 使用 `DataProxyHandle.get()` 读取快照，使用 `on('dataChange')` 监听变化。
3. 纯读取不得发送 Want，也不得借 `start_instance` 做状态探测。
4. 所选实例在有效快照中为 `running` 时，RustDesk 直接恢复原远控/观看/相机/文件传输连接，不拉起 EasyTier。
5. 所选实例不是 `running` 时，RustDesk 才能发布 `start_instance` 请求并显式拉起 EasyTier。
6. EasyTier 必须先确认内核真实 `running`，再发布新的 running 快照，然后发布命令结果，最后 Want 拉回 RustDesk。
7. 过期或格式无效的快照不能作为 running 证据。RustDesk 必须重新 `get()`；仍无法得到有效快照时显示“状态无法确认”，不得静默绕过 EasyTier 直接连接。

## 2. 固定身份

| 项目 | EasyTier | RustDesk |
| --- | --- | --- |
| bundleName | `top.frankhan.easytier` | `top.frankhan.resk` |
| appIdentifier | `6917581172490635834` | `6917605780518421882` |
| moduleName | `entry` | `entry` |
| abilityName | `EntryAbility` | `EntryAbility` |

## 3. v2 常量

| 项目 | 值 |
| --- | --- |
| schemaVersion | `2` |
| 启动请求 operation | `start_instance` |
| 请求 action | `top.frankhan.easytier.action.START_INSTANCE_REQUEST` |
| 结果 action | `top.frankhan.easytier.action.START_INSTANCE_RESULT` |
| requestId 参数键 | `top.frankhan.easytier.api.requestId` |
| operation 参数键 | `top.frankhan.easytier.api.operation` |
| RustDesk 请求 URI | `datashareproxy://top.frankhan.resk/easytier_api/v2/start_request` |
| EasyTier 能力 URI | `datashareproxy://top.frankhan.easytier/third_party_api/v2/capabilities/rustdesk` |
| EasyTier 快照 URI | `datashareproxy://top.frankhan.easytier/third_party_api/v2/instance_snapshot/rustdesk` |
| EasyTier 结果 URI | `datashareproxy://top.frankhan.easytier/third_party_api/v2/start_result/rustdesk` |
| 快照 TTL | `15000` 毫秒 |

所有 URI 都是固定值。不得按 requestId 或实例 ID 动态创建 URI，以免触发每个应用最多 32 个共享配置项的限制。

## 4. 实例快照

EasyTier 安装时注册快照 URI；应用初始化后立即发布快照，此后每 500ms 检查实例列表、状态和对端数变化，并且至少每 5 秒发布一次心跳。快照结构：

```json
{
  "schemaVersion": 2,
  "updatedAt": 1785600000000,
  "ttlMs": 15000,
  "instances": [
    {
      "instanceId": "office-network",
      "instanceName": "办公网络",
      "state": "running",
      "peerCount": 3,
      "virtualIpv4": "10.126.126.2"
    }
  ],
  "truncated": false
}
```

字段语义：

| 字段 | 语义 |
| --- | --- |
| `updatedAt` | EasyTier 发布该快照时的 Unix 毫秒时间戳 |
| `ttlMs` | 固定为 `15000`；`now - updatedAt > ttlMs` 时快照失效 |
| `instances` | 最多 10 个已保存实例；没有实例时是合法的空数组 `[]` |
| `truncated` | 保存实例超过 10 个时为 `true`，调用方不得把未列出的实例判断成 stopped |
| `state` | `stopped`、`starting` 或 `running` |
| `peerCount` | 每个实例都存在；非 running 时为 `0` |
| `virtualIpv4` | 仅在 EasyTier 已取得有效地址时存在 |

安装包内的静态初始快照使用 `updatedAt: 0`，它只负责让 URI 可被 `get/on`，永远不能作为有效运行状态。

### 快照有效性

RustDesk 必须同时满足以下条件才接受快照：

- `schemaVersion === 2`
- `updatedAt` 是正整数
- `ttlMs === 15000`
- `updatedAt` 不比本机时间晚超过 5 秒
- `Date.now() - updatedAt <= ttlMs`
- `instances` 是数组，所选实例字段格式有效

有效快照中的空列表表示“EasyTier 当前没有保存的实例”，不是读取错误。`get()` 返回 `URI_NOT_EXIST`、`NO_PERMISSION`、值无法解析、版本不匹配或快照过期都属于“状态无法确认”。

## 5. RustDesk 读取与订阅

RustDesk 不需要启动 EasyTier 即可读取最近一次静态/动态快照：

```arkts
const handle = await dataShare.createDataProxyHandle()
const config: dataShare.DataProxyConfig = {
  type: dataShare.DataProxyType.SHARED_CONFIG
}
const results = await handle.get([
  'datashareproxy://top.frankhan.easytier/third_party_api/v2/instance_snapshot/rustdesk'
], config)
```

进入需要显示 EasyTier 状态的页面或等待启动结果时订阅同一个 URI：

```arkts
const callback = (error: BusinessError<void>, changes: dataShare.DataProxyChangeInfo[]): void => {
  if (error) {
    return
  }
  // 校验 URI、解析 value、检查 schemaVersion/updatedAt/ttlMs 后再更新状态。
}
handle.on('dataChange', [snapshotUri], config, callback)
```

页面销毁或不再等待时必须用相同 callback 调用 `off('dataChange', ...)`。订阅通知是增量提示，RustDesk 在订阅成功后仍应先主动 `get()` 一次，避免错过订阅前的最新值。

## 6. RustDesk 的连接决策

```text
用户发起 RustDesk 连接
→ get 最近快照并校验 TTL
→ 所选实例存在且 state=running
   → 不发送 EasyTier Want，直接恢复原 RustDesk 连接
→ 所选实例为 stopped/starting/不存在
   → 保存原目标、连接类型和 requestId
   → 发布 start_instance 请求并拉起 EasyTier
→ 快照过期或读取失败
   → 再 get 一次
   → 仍无有效快照：显示“EasyTier 状态无法确认”
   → 不得静默直接连接；用户继续连接时才可发送 start_instance 拉起 EasyTier刷新/启动
```

当 `truncated=true` 且所选实例不在列表时，只能判定为“未出现在快照”，不能判定实例不存在。调用方应要求用户在 EasyTier 中重新选择，或通过 `start_instance` 让 EasyTier按已保存 ID 校验。

## 7. RustDesk 发布启动请求

RustDesk 在 `module.json5` 注册：

```json5
"crossAppSharedConfig": "$profile:easytier_api_shared_config"
```

对应 profile：

```json
{
  "crossAppSharedConfig": [
    {
      "uri": "datashareproxy://top.frankhan.resk/easytier_api/v2/start_request",
      "value": "{\"schemaVersion\":2,\"requestId\":\"\",\"operation\":\"start_instance\",\"issuedAt\":0,\"instanceId\":\"\"}",
      "allowList": ["6917581172490635834"]
    }
  ]
}
```

请求载荷：

```json
{
  "schemaVersion": 2,
  "requestId": "12345678-1234-4234-9234-123456789abc",
  "operation": "start_instance",
  "issuedAt": 1785600000000,
  "instanceId": "office-network"
}
```

规则：

- `requestId` 必须是小写 UUID v4，每次操作使用新值。
- 请求有效期为 5 分钟，允许最多 5 秒未来时钟偏差。
- 远控目标、会话类型、密码和网络密钥不得发布给 EasyTier。
- v2 仅接受 `start_instance`；`ensure_instance_running`、`list_instances` 和 `query_instance` 均不再兼容。

发布成功后发送显式 Want：

```arkts
const want: Want = {
  bundleName: 'top.frankhan.easytier',
  moduleName: 'entry',
  abilityName: 'EntryAbility',
  action: 'top.frankhan.easytier.action.START_INSTANCE_REQUEST',
  uri: 'datashareproxy://top.frankhan.resk/easytier_api/v2/start_request',
  parameters: {
    'top.frankhan.easytier.api.requestId': requestId,
    'top.frankhan.easytier.api.operation': 'start_instance'
  }
}
await context.startAbility(want)
```

系统注入的调用方 bundleName/appIdentifier 由 EasyTier 校验，RustDesk 不得手动填写对应系统字段。

## 8. EasyTier 启动处理顺序

```text
收到 start_instance Want
→ 校验 action、request URI、系统调用方身份和 requestId
→ get RustDesk 固定请求 URI
→ 校验 schemaVersion、operation、TTL 和 instanceId
→ 持久化 requestId 防重放
→ 实例已 running：不重启
→ 实例 starting：等待现有启动完成
→ 实例 stopped：停止当前其他实例并启动所选实例
→ 等待内核真实 running 快照
→ 强制 publish 最新实例快照
→ publish start_result
→ 显式 Want 拉回 RustDesk
```

如果 running 快照发布失败，EasyTier 返回 `SNAPSHOT_PUBLISH_FAILED`，不会把“仅内核运行但调用方不可验证”伪装成完整成功。

## 9. 启动结果与回调

成功结果：

```json
{
  "schemaVersion": 2,
  "requestId": "12345678-1234-4234-9234-123456789abc",
  "operation": "start_instance",
  "issuedAt": 1785600005000,
  "ok": true,
  "code": "OK",
  "message": "EasyTier 实例已启动并由内核确认运行",
  "instance": {
    "instanceId": "office-network",
    "instanceName": "办公网络",
    "state": "running",
    "peerCount": 3,
    "virtualIpv4": "10.126.126.2"
  }
}
```

回调 Want：

```text
bundleName  = top.frankhan.resk
moduleName  = entry
abilityName = EntryAbility
action      = top.frankhan.easytier.action.START_INSTANCE_RESULT
uri         = datashareproxy://top.frankhan.easytier/third_party_api/v2/start_result/rustdesk
parameters[top.frankhan.easytier.api.requestId] = requestId
parameters[top.frankhan.easytier.api.operation] = start_instance
```

RustDesk 必须在冷启动和热启动入口走同一个回调处理函数，并校验：

1. action、结果 URI、EasyTier bundleName 与 appIdentifier。
2. Want requestId 与本地 pending request 完全一致。
3. `get()` 结果的 schemaVersion、requestId、operation、issuedAt、ok/code。
4. 同时读取/等待有效快照，确认同一 instanceId 的 `state=running`。
5. 只有结果与快照都确认 running 后才恢复原 RustDesk 连接。
6. 失败、取消或超时都清理 pending 状态，不得自动降级直连。

主要结果码：`OK`、`INVALID_REQUEST`、`REQUEST_EXPIRED`、`REPLAYED_REQUEST`、`BUSY`、`INSTANCE_NOT_FOUND`、`START_REJECTED`、`RUNTIME_TIMEOUT`、`SNAPSHOT_PUBLISH_FAILED`、`INTERNAL_ERROR`。

## 10. 当前实现位置与验证边界

- `entry/src/main/ets/services/integration/ThirdPartyApiContract.ets`
- `entry/src/main/ets/services/integration/ThirdPartyApiService.ets`
- `entry/src/main/ets/entryability/EntryAbility.ets`
- `entry/src/main/resources/base/profile/third_party_shared_config.json`
- `entry/src/main/module.json5`

EasyTier 提供方负责快照、启动和回调。RustDesk 消费端仍需按本文实现 `get/on/off`、快照有效性检查、启动请求及回调校验；任何单端构建成功都不等于双应用流程已经联调成功。
