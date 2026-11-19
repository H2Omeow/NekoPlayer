# 服务端部署说明

NekoPlayer 的账号、云同步、社区、视频与云存储能力依赖自建服务：

- 账户中心：`account.nekoh2o.top`（Node.js + Express，用户数据存 `users.json`）
- 播放与社区 API：`player.nekoh2o.top`（Node.js 24，`node:sqlite`；云同步数据加密落盘）
- 对象存储：S3 兼容服务（雨云 ROS），私有桶 + 服务端预签名，客户端直传

以下为各模块的接入方式与约束。

## 1. 账户中心

- 依赖：`express`、`bcrypt`、`jsonwebtoken`、`cookie-parser`、`multer`、`nodemailer`、`uuid`。
- 数据：`users.json` 保存用户、密码哈希与 `thirdPartyBindings`。
- 第三方：彩虹聚合登录（`src/routes/rainbow.js`）与森空岛扫码 / 短信 / 密码绑定（`src/routes/skland.js`）。
- 森空岛绑定使用鹰角公开的扫码与手机号接口；只保存用户 ID 与凭证，不读取游戏数据。需要 `express.json()` 中间件，否则 JSON 请求体为空。

## 2. 播放、云同步与社区 API

- 需要 Node.js 24（`node:sqlite`）。
- 将 `deploy/site-comments.mjs` 放到服务目录，在 Express 应用安装会话中间件之后、SPA 兜底路由之前调用：

```js
import { installSiteComments } from './site-comments.mjs';
installSiteComments(app, {
  dataRoot,
  resolveUser,
  jsonParser: express.json({ limit: '16kb' }),
});
```

- `resolveUser(req)` 必须校验 Bearer JWT 并返回 `{ user: { id, username } }`，无效凭据返回 `null`。写操作只接受通过校验的 Bearer 身份。
- 数据位于 `dataRoot/comments/comments.sqlite`；备份时同时保留 WAL，或使用 SQLite 一致性备份。

## 3. 云存储

- 环境变量：`ROS_ENDPOINT`、`ROS_ACCESS_KEY`、`ROS_SECRET_KEY`、`ROS_BUCKET_FREE`、`ROS_BUCKET_SPONSOR`。
- 桶保持私有，客户端通过 `POST /files/upload-url` 或分片接口获取预签名地址后直传；服务端只做配额校验、HEAD 校验与流量记账。
- 额度、订单与人工审核数据位于 `data/cloud/cloud.sqlite`；管理面板入口 `/admin`，写操作写入审计表。
- 免费用户连续 180 天未登录会清理其上传文件（不涉及歌单、收藏、播放记录），清理前 7 天写入站内信。

## 4. 酷狗与原生接口

- 网易云、酷狗接口已在 Kotlin/OkHttp 内实现（weapi/eapi、酷狗原版/概念版签名与设备注册），无需手机内运行 Node.js。
- 如需部署酷狗 API 备用：原版与概念版各自进程，平台由启动参数决定：

```bash
HOST=127.0.0.1 pm2 start app.js --name KuGouMusicApi-lite -- --platform=lite --port=4001
pm2 save
```

- 将 `deploy/kugou-platform-router.cjs` 复制为 API 目录下的 `platform-router.cjs`，在创建 Express 应用后、解析请求体与缓存中间件之前加入：

```js
if (process.env.platform !== 'lite') app.use(require('./platform-router.cjs')());
```

- `platform=0` 使用原版，`platform=1` 转发到本机概念版 4001；4001 只监听回环地址。

## 5. 校验

- 服务端单测：`node --test deploy/*.test.*`
- Android：`./gradlew :app:testDebugUnitTest :app:lintDebug`
- 设置 `NATIVE_API_SMOKE=1` 可运行不发送短信/评论的公开接口联通测试。
- 上游接口可能随时变化，应用保留真实错误信息，不生成假的登录状态。
