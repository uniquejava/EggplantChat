# EggplantChat

用于 macOS 和 Windows 的局域网聊天工具，支持富文本、图片和文件附件。

## 启动项目

准备 Flutter 3.47.5 或兼容版本。macOS 需要 Xcode 和 CocoaPods，Windows 需要带有 C++ 桌面开发组件的 Visual Studio。

```bash
flutter pub get
flutter run --profile -d macos
```

在 Windows 上运行：

```powershell
flutter pub get
flutter run --profile -d windows
```

剪贴板插件首次构建会编译 Rust 代码，或下载上游提供的二进制文件。依赖版本记录在 `pubspec.lock`，不需要强制覆盖依赖。

## 连接另一台电脑

1. 在同一局域网的两台电脑上运行应用。
2. 允许系统提示的本地网络访问。在 Windows 防火墙提示中允许专用网络通信。
3. 在两台电脑上分别点击 **连接设备**。窗口显示本机 IP、端口和六位配对码。
4. 在其中一台电脑上输入另一台的 IP、端口和配对码，点击 **连接**。也可以点击附近设备开始配对。
5. 选择左侧会话，输入消息或添加附件，然后点击 **发送**。

配对窗口开放五分钟。配对后，两台设备都可以发送消息和附件，后续启动不需要重复配对。只有应用运行时才能接收消息。

自动发现使用 UDP 53319，消息和附件使用 HTTPS TCP 53318。自动发现被网络阻止时，可以手动输入 IP。访客 Wi-Fi、AP 隔离或 VPN 可能阻止电脑互相访问。

## 发送带格式的内容

从网页、Word 或其他提供 HTML 剪贴板内容的应用复制文本，粘贴到编辑区。也可以使用编辑区的加粗、斜体、下划线、列表、引用和代码块按钮。

消息使用 Quill Delta 保存和传输，保留支持的文字样式、空格和换行。收到消息后，点击消息下方的复制按钮，同时写入 HTML 和纯文本，目标应用可以选择支持的格式。

Enter 换行。macOS 使用 Command + Enter 发送，Windows 使用 Ctrl + Enter 发送。

复杂表格、Word 分页和原应用的全部 CSS 版式不保证还原。需要完整保留原稿时，发送原文件。图片通过选择、拖拽或粘贴进入待发送区，嵌入网页中的图片请单独添加。

## 收发附件

点击图片或附件按钮，或将文件拖入编辑区。点击待发送附件可以移除它。文件夹需要先压缩。

单个附件最大 10 GB。传输显示进度，失败的发送消息可以重试。接收端完成大小和 SHA-256 校验后才标记成功。点击 **另存为** 选择保存位置。

应用在本地数据目录保存会话、配对信息和收发附件副本。可以在 **本机设置** 查看目录。关闭应用后不接收消息；当前版本没有托盘常驻、离线消息服务器或自动剪贴板广播。

## 构建与检查

```bash
flutter analyze
flutter test
flutter build macos --release
```

在 Windows 上执行 `flutter build windows --release`。macOS 产物位于 `build/macos/Build/Products/Release/EggplantChat.app`。

传输使用本地生成的 TLS 证书。首次配对信任输入的局域网地址，后续连接固定对方的证书指纹。首次配对应在可信局域网完成；六位配对码不能独立防御首次连接中的主动中间人攻击。聊天记录在磁盘上不额外加密。

## 使用的库

- [shadcn_ui](https://pub.dev/packages/shadcn_ui)：界面组件和 Lucide 图标。
- [Flutter Quill](https://pub.dev/packages/flutter_quill)：富文本编辑、HTML 粘贴和消息显示。
- [super_clipboard](https://pub.dev/packages/super_clipboard)：HTML、纯文本和图片剪贴板。
- [file_selector](https://pub.dev/packages/file_selector)、[desktop_drop](https://pub.dev/packages/desktop_drop)：系统文件对话框和拖拽。
- [basic_utils](https://pub.dev/packages/basic_utils)、[crypto](https://pub.dev/packages/crypto)：本地证书生成和文件校验。
- Dart 标准库：HTTPS、UDP 发现和流式文件 IO。

界面约定见 [docs/design.md](docs/design.md)。
