# AGCD v3 本地构建与 GitHub Actions 校验说明

本仓库（`EasyTier / 鸿蒙原生`，`projectId: easytier-arkts`，`bundleName: top.frankhan.easytier`）已切换至本地 AGCD v3 统一构造、签名与 AGC 分发流程。

## 安全边界与 GitHub Actions 职责

- **公网 CI 仅做纯编译校验**：`.github/workflows/ohos.yml` 不拉取私有签名仓库、不配置 AGC 密钥、不执行签名，也不向 GitHub Artifacts 上传任何 `.hap` 或 `.app` 产物。
- **本地 AGCD 统一出包与签名**：正式构建与签名均在本地工作区由 AGCD 执行，基于无签名 Release 产物签出 OpenHarmony 无签名 `.hap`、HarmonyOS OAuth Debug 临时签名 `.hap` 与 OAuth 云管理签名 `.app`。

## 本地无签名 Release 构建入口

构建前 AGCD 会向工作区根目录注入上游缓存产物 `easytier-ohrs-0.0.1.har` 与分类更新日志 `agcd-changelog.json`。`hvigorfile.ts` 会在构建期自动：

1. 校验 `easytier-ohrs-0.0.1.har` 的 SHA-256，若与 `oh_modules/.easytier-ohrs-har.sha256` 不一致则自动解压同步到 `oh_modules/easytier-ohrs`；
2. 读取 `agcd-changelog.json`（若存在），通过 `appContext.setAppJsonOpt` 注入 `versionName` 与 `versionCode`，并同步生成 `BuildTime.ets` 与 `AgcdChangelog.ets`（未存在 `agcd-changelog.json` 时自动回退到仓库默认本地开发配置）。

标准无签名构建命令：

```bash
hvigorw assembleHap --no-daemon -p buildMode=release -p enableSignTask=false
hvigorw assembleApp --no-daemon -p product=publish -p buildMode=release -p enableSignTask=false
```
