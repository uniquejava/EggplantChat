import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    #if DEBUG
    if ProcessInfo.processInfo.environment["EGGPLANT_CHAT_TEST_PASTEBOARD"] == "1",
       let method = class_getClassMethod(NSPasteboard.self, #selector(getter: NSPasteboard.general)) {
      let pasteboard = NSPasteboard.withUniqueName()
      let getPasteboard: @convention(block) (AnyObject) -> NSPasteboard = { _ in pasteboard }
      method_setImplementation(method, imp_implementationWithBlock(getPasteboard))
      let channel = FlutterMethodChannel(
        name: "eggplant_chat/test_pasteboard",
        binaryMessenger: flutterViewController.engine.binaryMessenger)
      channel.setMethodCallHandler { _, result in result(true) }
    }
    #endif

    super.awakeFromNib()
  }
}
