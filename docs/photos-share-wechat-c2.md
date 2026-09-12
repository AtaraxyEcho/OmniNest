# 照片分享微信接入（C2）方案留存

> 状态：**暂缓**。当前未申请微信开放平台，产品侧保持 C1 降级（复制链接）。
> 适用仓库：OmniNest 根仓库。实现时请以本文件为规格，避免与已合入代码冲突。

## 背景

- C1 已合入：`PhotoShareChannel` 抽象；分享宫格微信/复制/二维码/更多。
- 未接 OpenSDK 时微信按钮降级为复制 `https://<publicWebBase>/share/{token}`。
- 分享链路已支持 `includeLocation` / `originalQuality`，并按策略过滤公开 DTO。

## 前置条件

1. 微信开放平台「移动应用」审核通过，取得 **AppID**。
2. Android：应用包名 + 应用签名（与开放平台一致）。
3. iOS（若做）：Universal Links、应用关联文件、Bundle Id 绑定。
4. 部署：`effectiveWebBaseUrl` 必须为**微信可访问的公网 HTTPS** 域名（卡片缩略图与打开链接）。

## 产品形态（定稿）

```text
点「微信」
  → 确保存在有效分享链（创建前已撤销旧有效链）
  → 调起微信「网页分享」
  → 标题 = 照片标题
  → 缩略图 = coverUrl（公网可达）
  → 链接 = https://<publicWebBase>/share/{token}
  → 对方在微信内打开现有公开页（密码/过期/策略仍生效）
```

**不做**：小程序卡片、Web 微信 JS-SDK、原图二进制直传微信。

## 工程落地

### 依赖

- 评估 `fluwx`（或当前维护中的 OpenSDK 封装）。
- AppID **不得**明文写入仓库；使用构建变量 / 安全配置注入。
- Web 包不打进 Android so；Desktop/Web 继续走 Unsupported + 复制。

### 代码

1. 新增 `photo_share_channel_io.dart`（或按平台条件导入）：

```dart
class WeChatPhotoShareChannel implements PhotoShareChannel {
  @override
  bool get supportsWeChat => true;

  @override
  Future<PhotoShareChannelResult> shareLinkToWeChat({
    required String title,
    required String webUrl,
    String? thumbUrl,
  }) async {
    // fluwx shareWeChat(WeChatShareWebPageModel(...))
    // 成功 PhotoShareChannelSuccess
    // 未装微信 / 未初始化 → Unsupported 或 Failure
  }
}
```

2. 修改 `photo_share_channel.dart` 中 `_resolvePhotoShareChannel()`：

```dart
// Android/iOS 且已配置 AppID → WeChatPhotoShareChannel
// 否则 → UnsupportedPhotoShareChannel
```

3. UI **不必改**：失败仍落到复制降级。

### 原生配置清单

| 平台 | 项 |
|---|---|
| Android | `AndroidManifest` 查询微信、AppID、签名校验 |
| iOS | URL Scheme、LSApplicationQueriesSchemes、Universal Links |
| 两端 | 初始化 fluwx（AppID 从构建配置读取） |

## 验收

- [ ] 已装微信：卡片分享成功，微信内打开公开页
- [ ] 未装微信 / 未配 AppID：可预期失败或降级复制，无崩溃
- [ ] 撤销 / 过期后旧卡片链接失效
- [ ] 关位置 / 关原图后，微信打开的公开页遵守策略
- [ ] Web/Desktop 无 fluwx 链接错误，复制仍可用

## 明确不做

- 小程序分享、原图 File 直传、Web JS-SDK、把 AppID 写进 git。

## 相关提交（参考）

| Commit | 说明 |
|---|---|
| `8bb49ae` | 分享 policy + 公开过滤 + 创建前撤销旧链 |
| `179cbfd` | 分享渠道抽象与微信降级复制 |
