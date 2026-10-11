import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var appearanceChannel: FlutterMethodChannel?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    let available = self.screen?.visibleFrame.size ?? NSSize(width: 1360, height: 860)
    windowFrame.size = NSSize(width: min(1360, available.width), height: min(860, available.height))
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 720, height: 480)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    appearanceChannel = FlutterMethodChannel(name: "chat.weilai.huabu/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    appearanceChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "hasUpdateKey" {
        result(!(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").isEmpty)
        return
      }
      guard call.method == "setBrightness" else { result(FlutterMethodNotImplemented); return }
      guard let value = call.arguments as? String, value == "dark" || value == "light" else {
        result(FlutterError(code: "invalid_brightness", message: "Expected dark or light", details: nil)); return
      }
      self?.appearance = NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
      self?.titlebarAppearsTransparent = true
      self?.backgroundColor = value == "dark"
        ? NSColor(srgbRed: 11/255, green: 13/255, blue: 20/255, alpha: 1)
        : NSColor(srgbRed: 248/255, green: 249/255, blue: 251/255, alpha: 1)
      result(nil)
    }

    super.awakeFromNib()
  }
}
