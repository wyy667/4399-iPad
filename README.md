# 4399 iPad 本地 Flash 浏览器原型

启动后直接全屏打开 `https://www.4399.com/`，没有地址栏和标签栏。使用 Swift / UIKit / WKWebView，内置 Ruffle 0.8.0，Flash 运行在 iPad 本机。网站和游戏素材仍需联网下载；不使用云游戏、远程电脑或远程执行。

## 在 iPad 上安装

需要 iPadOS 16.4 或以上的 iPad。仓库已配置 GitHub Actions：推送到 `main` 或手动运行 **Build re-signable iPad IPA**，会使用 macOS/Xcode 编译并上传 `Flash4399-resignable-ipa` artifact。解压得到 IPA 后，用你自己的签名工具签名安装；产物不含开发者证书签名或 provisioning profile。

从 0.1.1 起，打包前先用苹果 `codesign -s -` 创建本地 ad-hoc 签名区与资源封印，再执行严格校验，避免向重新签名工具提供完全没有签名区的可执行文件。这不是用于设备安装的开发者 Ad Hoc 分发签名，仍须重新签名。此改动用于排查 0.1.0 在全能签中的安装失败，尚未确认具体失败原因或真机修复结果。

也可在装有 Xcode 的 Mac 上直接安装：

1. 将整个工程文件夹复制到 Mac，双击 `Flash4399.xcodeproj`。
2. 在 target `Flash4399` 的 **Signing & Capabilities** 中选择自己的 Apple Team，将 Bundle Identifier 改为自己的唯一标识。
3. 连接 iPad，按 Xcode 提示完成设备信任、开发者模式等设置，选择该 iPad 作为运行目标。
4. 点击 Run。播放器 JS 和两份 WASM 已随工程附带，不需要在 Mac 上安装 Node 或下载播放器。

可先在 Mac 上检查模拟器构建：

```sh
xcodebuild -project Flash4399.xcodeproj -scheme Flash4399 \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

这是开发原型，没有配置商店图标或发行签名。

## 使用

- 启动自动进入 4399，采用桌面浏览模式，避免网站直接转到移动游戏目录。
- 点击游戏画面使其获得焦点，再使用外接键盘；鼠标点击和移动走 WebKit 原生输入。
- 点击需要新窗口的链接会在当前窗口打开。
- **三指轻点**或 **⌘ + ,** 打开隐藏菜单，可返回上一页、回首页、刷新、打开播放器自检。
- 自检页面不依赖游戏服务器。蓝色舞台中应出现绿色方块；点击舞台后按住 D，方块右移，松开恢复。
- 页面使用持久化网站数据存储。具体游戏存档是否兼容，仍要逐款验证。

“全屏”指 App 没有浏览器工具栏且隐藏状态栏，网页填满 App 窗口；没有修改 4399 的页面布局，也不会自动把某一个游戏单独放大。系统保留退出 App 的手势，Home 指示条由系统控制自动隐藏。

## 已验证与未验证

自动化测试在 Windows 的 Playwright Chromium 和 WebKit 中运行，使用模拟的原生资源桥，不是 iPad 模拟器：

- 两个引擎均通过自制 SWF 的实际像素渲染检查。
- ActionScript `Key.isDown` 能收到 D 键，方块按下右移、松开恢复。
- 动态创建 Flash 元素、iframe 中的元素能够被替换并加载。
- 方向键不滚动页面，失焦/退出操作可释放跟踪的按键，普通输入框保持正常。
- 校验播放器不通过网络下载 WASM。
- 模拟素材 CDN 跨域失败后，走受限原生资源桥完成 SWF 加载；无关域名不会进入桥接。
- Xcode 工程语法和 Info.plist 已解析检查；这不等同于 Swift 编译通过。

**未验证：** iPad 真机上的 WKScriptMessageHandlerWithReply 桥接、性能/声音/外接键鼠、具体 4399 游戏完整关卡与存档。不要把上述自检通过理解为冒险王或全部 4399 游戏已兼容。

## 实现边界

- Ruffle 的 JavaScript 以 WKUserScript 在各 frame 的页面开始时注入；补充 ready 事件扫描以处理 WebKit iframe 初始化时序。
- 使用 WebKit 公开内容规则，仅阻止 `/jss/flashopen1.js`：这个旧插件检测器在约 600 毫秒后就会删除游戏区，早于 WASM 初始化完成。播放器自身负责显示加载失败信息；不修改网站登录或年龄验证逻辑。
- WASM 从 App Bundle 分块读取，通过仅允许固定文件名的只读消息桥提供给播放器，避免 CDN 依赖和大块 base64 峰值。
- 4399 的游戏 CDN 没有提供网页 CORS 响应头。仅当网页 GET 失败时，使用 URLSession 读取 HTTPS 的 `4399.com` / `5054399.com` 下 `/4399swf/` 或 `/upload_swf/` 素材路径，按 256 KB 分块传回播放器。只接受来自这些站点的 frame，不带 Cookie，不代理账号请求；限制单文件 64 MB、缓存 8 个文件，并校验重定向。无通用网络代理或 WebKit 私有 API。其他跨域资源、CSP、登录和失效服务仍可能阻止游戏运行。
- 4399 的 Flash 检测与加载器依赖 ExternalInterface，因此仅在 `4399.com`、`5054399.com` 及其子域启用 SWF 与网页脚本交互，其他域默认关闭。
- 键鼠采用系统原生网页输入，不做全局合成按键注入；3D FPS 的相对鼠标/指针锁定不在本版范围。
- 为旧站点设置 `NSAllowsArbitraryLoadsInWebContent`，只放宽 WebView 的 ATS；这不会关闭浏览器的混合内容和跨域限制。
- 新窗口合并到当前窗口；依赖 `window.opener` 的登录弹窗可能需要后续适配。

## 开发验证

```sh
npm ci
npx playwright install chromium webkit
npm test
```

`scripts/create-project.py` 可重建 Xcode 工程，`scripts/create-selftest.py` 可重建原创 SWF 样例。
`node scripts/check-live.cjs <4399游戏介绍页URL>` 用于只读在线诊断，结果写到 `artifacts/`，不会登录或提交账号信息。

## 第三方资源

Ruffle 0.8.0 来自官方 release 的 `ruffle-0.8.0-web-selfhosted.zip`：
https://github.com/ruffle-rs/ruffle/releases/tag/v0.8.0

原始播放器文件未修改，许可证位于 `Flash4399/WebAssets/Ruffle/LICENSE_MIT` 和 `LICENSE_APACHE`。
工程未打包任何 4399 商业游戏素材。自检 SWF 由本工程脚本生成。
