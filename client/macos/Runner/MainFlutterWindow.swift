import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var appearanceChannel: FlutterMethodChannel?
  private var imageFolderAccess: [String: (URL, Int)] = [:]
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    backgroundColor = NSColor(srgbRed: 11/255, green: 13/255, blue: 20/255, alpha: 1)
    flutterViewController.backgroundColor = backgroundColor
    titlebarAppearsTransparent = true
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
      if self?.handleImageFolder(call, result: result) == true { return }
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

  private func handleImageFolder(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    let defaults = UserDefaults.standard
    if call.method == "chooseImageFolder" {
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = true
      panel.prompt = "保存图片到此文件夹"
      panel.beginSheetModal(for: self) { response in
        guard response == .OK, let url = panel.url else { result(nil); return }
        do {
          let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
          var bookmarks = defaults.dictionary(forKey: "huabuImageFolders") as? [String: Data] ?? [:]
          bookmarks[url.path] = bookmark
          defaults.set(bookmarks, forKey: "huabuImageFolders")
          result(url.path)
        } catch { result(FlutterError(code: "image_folder", message: "保存目录授权失败，请重新选择文件夹", details: nil)) }
      }
      return true
    }
    guard ["accessImageFolder", "releaseImageFolder", "openImageFolder"].contains(call.method) else { return false }
    guard let path = call.arguments as? String else { result(FlutterError(code: "image_folder", message: "缺少保存目录", details: nil)); return true }
    if call.method == "openImageFolder" { result(NSWorkspace.shared.open(URL(fileURLWithPath: path))); return true }
    if call.method == "releaseImageFolder" {
      if let (url, count) = imageFolderAccess[path] {
        if count > 1 { imageFolderAccess[path] = (url, count - 1) }
        else { url.stopAccessingSecurityScopedResource(); imageFolderAccess.removeValue(forKey: path) }
      }
      result(nil)
      return true
    }
    if let (url, count) = imageFolderAccess[path] { imageFolderAccess[path] = (url, count + 1); result(url.path); return true }
    var bookmarks = defaults.dictionary(forKey: "huabuImageFolders") as? [String: Data] ?? [:]
    guard let bookmark = bookmarks[path] else { result(path); return true }
    do {
      var stale = false
      let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
      guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
      imageFolderAccess[path] = (url, 1)
      if stale, let refreshed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
        bookmarks[path] = refreshed
        defaults.set(bookmarks, forKey: "huabuImageFolders")
      }
      result(url.path)
    } catch { result(FlutterError(code: "image_folder", message: "无法访问图片文件夹，请重新选择原目录授权", details: nil)) }
    return true
  }
}
