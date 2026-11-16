import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // the same first size as on Windows, centred; never smaller than the side panel needs
    self.setContentSize(NSSize(width: 1360, height: 860))
    self.contentMinSize = NSSize(width: 1000, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
