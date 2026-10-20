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
  private var entries: [(SharedTextRecord, Data?)] = []
  private let storageQueue = DispatchQueue(label: "com.github.gemsnote.share-extension")

  override func viewDidLoad() {
    super.viewDidLoad()
    title = NativeLanguage.text("保存到 Gemsnote", "Save to Gemsnote")
    placeholder = NativeLanguage.text("保存后，请打开 Gemsnote 选择账号和笔记本完成导入",
      "After saving, open Gemsnote and choose an account and notebook to import.")
    navigationItem.rightBarButtonItem?.title = NativeLanguage.text("保存", "Save")
    navigationItem.leftBarButtonItem?.title = NativeLanguage.text("取消", "Cancel")
    navigationItem.prompt = NativeLanguage.text("保存后打开 Gemsnote 完成导入",
      "Open Gemsnote after saving to finish importing")
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
    ready && !saving && !entries.isEmpty
  }

  override func didSelectPost() {
    guard isContentValid() else { return }
    saving = true
    textView.isEditable = false
    validateContent()
    let batch = entries
    storageQueue.async { [weak self] in
      do {
        try SharedTextStore.appGroup().enqueueBatch(batch)
        DispatchQueue.main.async {
          self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
      } catch {
        DispatchQueue.main.async {
          guard let self else { return }
          self.saving = false
          self.textView.isEditable = false
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
    guard items.count <= 8, providers.count <= 8 else {
      showError("一次最多分享 8 项")
      return
    }
    guard !providers.isEmpty else {
      accept(items.compactMap { $0.attributedContentText?.string }.joined(separator: "\n\n"), generation: generation)
      return
    }
    loadProvider(providers, index: 0, generation: generation)
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
      guard let self, self.loadGeneration == generation, !self.ready else { return }
      self.loadGeneration += 1
      self.entries = []
      self.showError("读取分享超时，请取消后重试")
    }
  }

  private func loadProvider(_ providers: [NSItemProvider], index: Int, generation: Int) {
    guard loadGeneration == generation else { return }
    guard index < providers.count else {
      ready = true
      textView.text = entries.map { $0.0.text }.joined(separator: "\n\n")
      validateContent()
      return
    }
    let provider = providers[index]
    let fileType = provider.registeredTypeIdentifiers.first {
      guard let type = UTType($0) else { return false }
      return type.conforms(to: .image)
    } ?? provider.registeredTypeIdentifiers.first {
      guard let type = UTType($0) else { return false }
      return type.conforms(to: .data) && !type.conforms(to: .text) && !type.conforms(to: .url)
    }
    if let fileType {
      provider.loadFileRepresentation(forTypeIdentifier: fileType) { [weak self] url, error in
        do {
          if let error { throw error }
          guard let url else { throw SharedTextStore.Failure("无法读取分享文件") }
          let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
          guard attributes[.type] as? FileAttributeType == .typeRegular,
            let size = attributes[.size] as? NSNumber,
            size.intValue > 0, size.intValue <= 32 * 1024 * 1024 else {
            throw SharedTextStore.Failure("文件为空或超过 32 MiB")
          }
          // Provider URLs expire when this callback returns; copy bytes here.
          let bytes = try Data(contentsOf: url)
          let name = url.lastPathComponent
          let kind = UTType(fileType)?.conforms(to: .image) == true ? "image" : "attachment"
          DispatchQueue.main.async {
            self?.append(text: name, bytes: bytes, name: name, kind: kind,
                         providers: providers, index: index, generation: generation)
          }
        } catch {
          let message = error.localizedDescription
          DispatchQueue.main.async { self?.fail(message, generation: generation) }
        }
      }
      return
    }
    let type: String
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      type = UTType.fileURL.identifier
    } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      type = UTType.url.identifier
    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      type = UTType.plainText.identifier
    } else {
      fail("无法读取此分享类型", generation: generation)
      return
    }
    provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] value, error in
      if type == UTType.fileURL.identifier, let url = value as? URL, url.isFileURL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
          if let error { throw error }
          let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
          guard attributes[.type] as? FileAttributeType == .typeRegular,
            let size = attributes[.size] as? NSNumber,
            size.intValue > 0, size.intValue <= 32 * 1024 * 1024 else {
            throw SharedTextStore.Failure("文件为空或超过 32 MiB")
          }
          let bytes = try Data(contentsOf: url)
          let name = url.lastPathComponent
          let kind = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true ? "image" : "attachment"
          DispatchQueue.main.async {
            self?.append(text: name, bytes: bytes, name: name, kind: kind,
                         providers: providers, index: index, generation: generation)
          }
        } catch {
          let message = error.localizedDescription
          DispatchQueue.main.async { self?.fail(message, generation: generation) }
        }
        return
      }
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
          self.fail(NativeLanguage.text("读取分享失败：", "Unable to read share: ") +
                    error.localizedDescription, generation: generation)
        } else {
          self.append(text: loaded, providers: providers, index: index, generation: generation)
        }
      }
    }
  }

  private func fail(_ message: String, generation: Int) {
    guard loadGeneration == generation else { return }
    loadGeneration += 1
    entries = []
    ready = false
    validateContent()
    showError(message)
  }

  private func append(text: String?, bytes: Data? = nil, name: String? = nil,
                      kind: String? = nil, providers: [NSItemProvider], index: Int, generation: Int) {
    guard loadGeneration == generation else { return }
    let record = SharedTextRecord(
      id: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24)),
      title: titleText, text: text ?? "", resourceKind: kind, resourceName: name, resourceSize: bytes?.count)
    guard (try? record.validate()) != nil,
      entries.reduce(0, { $0 + ($1.1?.count ?? 0) }) + (bytes?.count ?? 0) <= 32 * 1024 * 1024 else {
      fail("分享内容无效、文本超过 256 KiB 或资源总大小超过 32 MiB", generation: generation)
      return
    }
    entries.append((record, bytes))
    loadProvider(providers, index: index + 1, generation: generation)
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
    entries = [(SharedTextRecord(id: recordID, title: titleText, text: text), nil)]
    textView.isEditable = false
    ready = true
    validateContent()
  }

  private func showError(_ message: String) {
    guard viewIfLoaded?.window != nil else {
      pendingError = message
      return
    }
    let alert = UIAlertController(title: NativeLanguage.text("未保存分享", "Share not saved"),
      message: NativeLanguage.error(message), preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: NativeLanguage.text("知道了", "OK"), style: .default))
    present(alert, animated: true)
  }
}
