# EggplantChat

局域网文件传输工具，基于 Flutter 开发。

![EggplantChat 局域网文件传输界面](docs/images/lan-file-transfer.png)

## 运行

需要 Flutter 3.47.5 或兼容版本，以及对应平台的桌面编译环境。

```bash
flutter pub get
flutter run --profile -d macos
```

Windows 将 `macos` 换为 `windows`。

## 使用

在同一局域网的设备上启动应用，选择附近设备即可传输。未发现设备时，可刷新列表或通过 IP 连接，默认端口为 `53318`。

单个文件最大 10 GB，文件夹需先压缩。接收文件保存在本地数据目录，可在应用设置中查看。

需允许本地网络访问和防火墙通信：TCP `53318` 用于传输，UDP `53319` 用于设备发现。

仅在可信局域网使用；本地聊天记录未额外加密。

## 开发

```bash
flutter analyze
flutter test
flutter build macos --release
```

Windows 构建使用 `flutter build windows --release`。

界面约定见 [docs/design.md](docs/design.md)。
