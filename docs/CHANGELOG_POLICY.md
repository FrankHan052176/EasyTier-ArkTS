# 更新记录维护方案

应用内更新记录分为“正式版”和“开发版”两条渠道，二者不能混用发布日期或版本号。

## 正式版

- 只在 AppGallery 正式版本发布后新增记录，版本号和日期以实际发布信息为准。
- 每条记录描述相对上一个正式版新增的用户可见能力与重要修复，发布后不再改写。
- 正式版页面展示“正式版”、版本号和构建日期，并提供获取开发版入口。
- 获取开发版入口旁提示“开发版更新更频繁，适合尝鲜用户”。

## 开发版

- 数组顶部只保留一条滚动更新的开发版记录，基线指向最近一个正式版。
- 仅记录已合入主线、可以由开发版构建获得的变化；更新内容时同步更新日期和
  `CHANGELOG_REVISION`。
- 开发版页面不展示获取开发版入口；开发版用户已经处于尝鲜渠道。
- 正式版页面的获取开发版入口跳转到 AppGallery 测试页：
  `https://appgallery.huawei.com/apptest/2MsGy1dzT1T`。

## AGCD 分类更新日志接入（`agcd-changelog.json`）

- 本地 AGCD 构建前会在仓库根目录生成 `agcd-changelog.json`，包含顶层 `versionName`、`versionCode`、`releaseDate`、`summary`，以及严格分类的 `mainProject`（主项目变更）和 `upstreams[]`（如 `et-core-job` 上游 Core HAR 变更）。
- `hvigorfile.ts` 在构建期读取 `agcd-changelog.json` 并写入 `AgcdChangelog.ets`；应用内 `ChangelogData.ets` 与 `ChangelogPage.ets` 将主项目与各上游变更按独立分组卡片展示，不按时间混排。
- 普通本地开发未放置 `agcd-changelog.json` 时，自动回退展示 `ChangelogData.ets` 中的静态记录，不影响编译与调试。

## 正式发布流程

1. 验收顶部开发版记录，并创建与目标 App 版本号一致的 GitHub Release。
2. Release 构建自动把该开发记录提升为正式记录，无需复制更新内容。
3. 发布后在主线把该条记录转为历史正式记录，并在顶部新增下一轮开发版记录。
4. 每次更新记录内容都递增 `CHANGELOG_REVISION`，确保本地 Debug 固定使用
   `0.0.1 / 99999999` 时也只会重新展示一次最新记录。
