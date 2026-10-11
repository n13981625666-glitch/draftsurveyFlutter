# Draft Survey 5.0.1 — Flutter 版

由原 Tauri 2（HTML/JS + Rust）工程完整移植到 Flutter（Dart）。计算逻辑、导出/导入数据格式、许可证流程、`.shipx` 船舶数据加密格式、许可证服务器均与原版保持一致。

> **重要：** 本工程是在没有 Flutter/Dart SDK 的环境里写成的，**尚未编译、尚未运行**。请先执行第 1 节的命令，把可能出现的编译/分析错误修掉（预计是零星的小问题），再做第 5 节的对照验证。

## 1. 第一次运行

```bash
node tools/select-ship.mjs XINHAITONG_26     # 选一条船（复制 .shipx 到 assets/ships/，生成应用标识）
node tools/bootstrap_platforms.mjs           # flutter create 生成 android/ windows/，并应用名称、包名、图标
flutter pub get
flutter analyze
flutter test
flutter run -d windows                       # 或 -d <android设备>
```

许可证服务器地址在构建时给定：`--dart-define=DS_LICENSE_URL=https://你的服务器`。

一步构建某条船：`node tools/ship-build.mjs XINHAITONG_26 build windows --release`（默认 `build apk --release`；环境变量 `DS_LICENSE_URL` 会自动传入）。

## 2. 目录

| 路径 | 作用 |
|---|---|
| `lib/core/app_model.dart` | 全部计算逻辑（原 `js/*.js`），`FieldStore` 以原 HTML 元素 id 存值，保证导出文件、服务器共享数据兼容 |
| `lib/core/{registry,field_store,ship,util,constants}.dart` | 字段注册表、船舶数据与校验、JS 语义工具（toFixed 等） |
| `lib/services/license.dart` | 激活、Ed25519 令牌校验、`license.bin` 机器绑定加密存储、6 小时在线复核、时钟回拨保护、共享数据同步、`.shipx` 解密 |
| `lib/services/pdf.dart` | 无依赖 PDF 生成（Draft Survey Report / Ballast Water Summary） |
| `lib/ui/*` | 主题、控件、各页面、外壳（标签页、对话框、导入导出） |
| `lib/main.dart` | 启动流程：启动页 → 许可证 → 船舶解密 → 主界面 |
| `server/`、`tools/`、`ships-lib/` | 许可证服务器与打包工具（逻辑不变，`select-ship` 等改为面向 Flutter） |

服务器与 `pack-ship` 用法与原版相同（`npm run setup`、`npm run pack-ship`、`npm run license-admin`、`npm run test:license`——服务器端测试已在本环境通过 23 项）。

## 3. 与 Tauri 版的差异

- **需要重新激活一次**：许可证文件位置变了（现在在应用支持目录）。桌面端机器码沿用原来的取值来源，所以同一台电脑的机器码不变。
- **Android**：机器码来自首次运行生成的安装 ID，卸载重装后会变化（需要服务器端重置设备）。
- PDF 导出：桌面端弹出“另存为”，手机端调起系统分享面板。
- 暂未实现 Tauri 版的 JS 混淆流程（Flutter 发布版本身为 AOT 编译；需要时可加 `--obfuscate --split-debug-info`）。
- 平台目录（android/、windows/）不入库，由 `bootstrap_platforms.mjs` 生成。

## 4. 已知限制

- 未编译、未跑 UI，布局细节（间距、窄屏）可能与原版有出入。
- `page_trimming.dart` 的 `_holdRow` 有几个未使用的命名参数（不影响运行，`flutter analyze` 会提示）。
- Android 的 release 构建使用默认调试签名；上架需自行配置 keystore。

## 5. 建议的验证

1. 用原版（Tauri）和本版输入同一组数据，比对 Initial/Final 结果、Sounding、Trimming、Stowage、Arrival 数值。
2. 在原版导出 JSON，在本版导入（再反向）确认互通。
3. 对比两版导出的 PDF。
4. 用 `server/` 完成激活、在线复核、吊销、共享数据拉取全流程。
