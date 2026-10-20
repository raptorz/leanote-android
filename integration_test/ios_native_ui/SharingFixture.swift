import UIKit

/// Test-only source app. Real UIActivityViewController providers cross the
/// system extension boundary; no production hooks or account are required.
@main
final class SharingFixture: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = FixtureController()
    window.makeKeyAndVisible()
    self.window = window
    return true
  }
}

final class FixtureController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let button = UIButton(type: .system)
    button.setTitle("Share image and file", for: .normal)
    button.addTarget(self, action: #selector(share), for: .touchUpInside)
    button.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(button)
    NSLayoutConstraint.activate([
      button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  @objc private func share(_ sender: UIButton) {
    do {
      let id = UserDefaults.standard.string(forKey: "fixture-id")!
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let imageURL = directory.appendingPathComponent("gemsnote-\(id).png")
      let fileURL = directory.appendingPathComponent("gemsnote-\(id).bin")
      let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
        UIColor.blue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
      }
      try image.write(to: imageURL)
      try Data("Gemsnote binary fixture \(id)\n".utf8).write(to: fileURL)
      let sheet = UIActivityViewController(activityItems: [imageURL, fileURL], applicationActivities: nil)
      sheet.popoverPresentationController?.sourceView = sender
      sheet.popoverPresentationController?.sourceRect = sender.bounds
      present(sheet, animated: true)
    } catch {
      let alert = UIAlertController(title: "Fixture error", message: error.localizedDescription, preferredStyle: .alert)
      present(alert, animated: true)
    }
  }
}
