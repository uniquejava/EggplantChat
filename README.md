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
3. 启动时会搜索设备 3 秒；另一台电脑稍后上线时，点击消息列表顶部的 **刷新设备**。点击左侧 **附近设备** 中的另一台电脑，即可直接开始聊天，无需配对码，也不需要对方打开连接窗口。
4. 使用固定 IP 时，点击 **通过 IP 连接**，输入对方的局域网 IP 和端口（默认 `53318`），点击 **连接**。
5. 选择左侧会话，输入消息或添加附件，然后点击 **发送**。

连接信息会自动保存，后续启动会通过保存的 IP 自动重连。两台设备都可以发送消息和附件，只有应用运行时才能接收消息。免配对直连需要两端都更新到当前版本。

自动发现使用 UDP 53319，消息和附件使用 HTTPS TCP 53318。自动发现被网络阻止时，可以手动输入 IP。访客 Wi-Fi、AP 隔离或 VPN 可能阻止电脑互相访问。

## 发送带格式的内容

从网页、Word 或其他提供 HTML 剪贴板内容的应用复制文本，粘贴到编辑区。编辑区仅保留图片、附件和发送按钮，不提供文字排版工具。

消息使用 Quill Delta 保存和传输，保留支持的文字样式、空格和换行。右键文本消息选择 **Copy**，同时写入 HTML 和纯文本，目标应用可以选择支持的格式。

Enter 发送，Shift + Enter 换行。

复杂表格、Word 分页和原应用的全部 CSS 版式不保证还原。需要完整保留原稿时，发送原文件。图片通过选择、拖拽或粘贴进入待发送区，嵌入网页中的图片请单独添加。

## 收发附件

点击图片或附件按钮，或将文件拖入编辑区。点击待发送附件可以移除它。文件夹需要先压缩。

单个附件最大 10 GB。传输显示进度，失败的发送消息可以重试。接收端完成大小和 SHA-256 校验后才标记成功。右键图片或附件，选择 **Save as…** 保存，选择 **Copy** 复制图片或文件。点击图片可放大、缩放和拖动查看。

右键消息选择 **Delete**，确认后删除本机聊天记录，对方记录不受影响。传输中的消息暂不可删除；删除记录不会清理附件副本。

应用在本地数据目录保存会话、连接信息和收发附件副本。可以在 **本机设置** 查看目录。关闭应用后不接收消息；当前版本没有托盘常驻、离线消息服务器或自动剪贴板广播。

## 构建与检查

```bash
flutter analyze
flutter test
flutter build macos --release
```

在 Windows 上执行 `flutter build windows --release`。macOS 产物位于 `build/macos/Build/Products/Release/EggplantChat.app`。

应用面向可信的家庭局域网，同一局域网内的设备可以直接建立连接并发送消息和附件。首次连接自动交换设备信息，后续连接校验已保存的证书和连接凭据。UDP 用于发现设备，文字、图片和文件仍通过 HTTPS 可靠传输。聊天记录在磁盘上不额外加密。

## 使用的库

- [shadcn_ui](https://pub.dev/packages/shadcn_ui)：界面组件和 Lucide 图标。
- [Flutter Quill](https://pub.dev/packages/flutter_quill)：富文本编辑、HTML 粘贴和消息显示。
- [super_clipboard](https://pub.dev/packages/super_clipboard)：HTML、纯文本和图片剪贴板。
- [file_selector](https://pub.dev/packages/file_selector)、[desktop_drop](https://pub.dev/packages/desktop_drop)：系统文件对话框和拖拽。
- [basic_utils](https://pub.dev/packages/basic_utils)、[crypto](https://pub.dev/packages/crypto)：本地证书生成和文件校验。
- Dart 标准库：HTTPS、UDP 发现和流式文件 IO。

界面约定见 [docs/design.md](docs/design.md)。
