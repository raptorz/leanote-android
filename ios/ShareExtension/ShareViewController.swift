import Social
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
  private let recordID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24))
  private var ready = false
  private var saving = false
  private var titleText = ""
  private var loadGeneration = 0
  private var pendingError: String?
  private let storageQueue = DispatchQueue(label: "com.github.gemsnote.share-extension")

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "保存到 Gemsnote"
    placeholder = "保存后，请打开 Gemsnote 选择账号和笔记本完成导入"
    navigationItem.rightBarButtonItem?.title = "保存"
    navigationItem.prompt = "保存后打开 Gemsnote 完成导入"
    textView.isEditable = false
    loadInput()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if let message = pendingError {
      pendingError = nil
      showError(message)
    }
  }

  override func didSelectCancel() {
    guard !saving else { return }
    loadGeneration += 1
    super.didSelectCancel()
  }

  override func isContentValid() -> Bool {
    guard ready, !saving else { return false }
    let record = SharedTextRecord(id: recordID, title: titleText, text: contentText ?? "")
    return (try? record.validate()) != nil
  }

  override func didSelectPost() {
    guard isContentValid() else { return }
    saving = true
    textView.isEditable = false
    validateContent()
    let record = SharedTextRecord(id: recordID, title: titleText, text: contentText ?? "")
    storageQueue.async { [weak self] in
      do {
        try SharedTextStore.appGroup().enqueue(record)
        DispatchQueue.main.async {
          self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
      } catch {
        DispatchQueue.main.async {
          guard let self else { return }
          self.saving = false
          self.textView.isEditable = true
          self.validateContent()
          self.showError(error.localizedDescription)
        }
      }
    }
  }

  private func loadInput() {
    loadGeneration += 1
    let generation = loadGeneration
    let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    titleText = String((items.first?.attributedTitle?.string ?? "").prefix(200))
    // Multiple providers must never be silently truncated to the first attachment.
    guard items.count == 1, providers.count <= 1 else {
      showError("目前仅支持分享单项文本或网页链接")
      return
    }
    guard let provider = providers.first else {
      accept(items.first?.attributedContentText?.string, generation: generation)
      return
    }
    let type: String
    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      type = UTType.url.identifier
    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      type = UTType.plainText.identifier
    } else {
      showError("此分享不是文本或网页链接，文件与图片接收尚未支持")
      return
    }
    provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] value, error in
      var text: String?
      if type == UTType.url.identifier {
        let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
        if let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          let host = url.host, !host.isEmpty {
          text = url.absoluteString
        }
      } else if let string = value as? String {
        text = string
      } else if let data = value as? Data, data.count <= 256 * 1024 {
        text = String(data: data, encoding: .utf8)
      }
      let loaded = text
      DispatchQueue.main.async {
        guard let self, self.loadGeneration == generation else { return }
        if let error {
          self.loadGeneration += 1
          self.showError("读取分享失败：\(error.localizedDescription)")
        } else {
          self.accept(loaded, generation: generation)
        }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
      guard let self, self.loadGeneration == generation, !self.ready else { return }
      self.loadGeneration += 1
      self.showError("读取分享超时，请取消后重试")
    }
  }

  private func accept(_ text: String?, generation: Int) {
    guard loadGeneration == generation else { return }
    loadGeneration += 1
    guard let text,
      (try? SharedTextRecord(id: recordID, title: titleText, text: text).validate()) != nil
    else {
      showError("分享内容为空、格式不支持或超过 256 KiB")
      return
    }
    textView.text = text
    textView.isEditable = true
    ready = true
    validateContent()
  }

  private func showError(_ message: String) {
    guard viewIfLoaded?.window != nil else {
      pendingError = message
      return
    }
    let alert = UIAlertController(title: "未保存分享", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }
}
