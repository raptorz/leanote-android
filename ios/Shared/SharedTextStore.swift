import Foundation
import Darwin

struct SharedTextRecord: Codable, Equatable {
  let id: String
  let title: String
  let text: String
  var accountKey: String = ""

  var dictionary: [String: String] {
    ["id": id, "title": title, "text": text, "accountKey": accountKey]
  }

  func validate() throws {
    guard id.utf8.count == 24,
      id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      title.utf8.count <= 8192, title.count <= 200, accountKey.utf8.count <= 8192,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !text.contains("\0"), text.utf8.count <= 256 * 1024
    else { throw SharedTextStore.Failure("分享文本无效或超过 256 KiB") }
  }
}

/// Shared by the containing app and extension. Every read/modify/write holds a
/// separate lock file: atomically replacing the JSON file must not replace the lock.
final class SharedTextStore {
  struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
  }

  private let directory: URL
  private var queueURL: URL { directory.appendingPathComponent("queue.json") }
  init(directory: URL) { self.directory = directory }

  static func appGroup() throws -> SharedTextStore {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "GemsnoteAppGroup") as? String,
      !group.isEmpty, !group.contains("$("),
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: group)
    else { throw Failure("无法访问分享收件箱，请检查 App Group 签名配置") }
    return SharedTextStore(directory: container.appendingPathComponent("SharedTextInbox"))
  }

  func peek() throws -> SharedTextRecord? { try locked { try read().first } }

  func enqueue(_ record: SharedTextRecord) throws {
    try record.validate()
    guard record.accountKey.isEmpty else { throw Failure("新分享不能预先绑定账号") }
    try locked {
      var records = try read()
      if let existing = records.first(where: { $0.id == record.id }) {
        guard existing.title == record.title, existing.text == record.text else {
          throw Failure("此分享已保存，不能覆盖其内容")
        }
        return
      }
      guard records.count < 8 else { throw Failure("收件箱已满，请先在 Gemsnote 处理待导入分享") }
      records.append(record)
      try write(records)
    }
  }

  func claim(id: String, accountKey: String) throws {
    guard !accountKey.isEmpty, accountKey.utf8.count <= 8192 else {
      throw Failure("分享目标账号无效")
    }
    try locked {
      var records = try read()
      guard let index = records.firstIndex(where: { $0.id == id }) else {
        throw Failure("待导入分享不存在")
      }
      guard records[index].accountKey.isEmpty || records[index].accountKey == accountKey else {
        throw Failure("此分享已绑定其他账号，请切换到该账号处理")
      }
      records[index].accountKey = accountKey
      try write(records)
    }
  }

  func acknowledge(id: String) throws {
    try locked {
      var records = try read()
      records.removeAll { $0.id == id }
      try write(records)
    }
  }

  private func read() throws -> [SharedTextRecord] {
    guard FileManager.default.fileExists(atPath: queueURL.path) else { return [] }
    let size = try FileManager.default.attributesOfItem(atPath: queueURL.path)[.size] as? NSNumber
    // JSON escaping can expand each input byte sixfold.
    guard let size, size.intValue <= 16 * 1024 * 1024 else {
      throw Failure("分享收件箱过大，未更改已有数据")
    }
    let records = try JSONDecoder().decode([SharedTextRecord].self, from: Data(contentsOf: queueURL))
    guard records.count <= 8, Set(records.map(\.id)).count == records.count else {
      throw Failure("分享收件箱数据无效，未更改已有数据")
    }
    try records.forEach { try $0.validate() }
    return records
  }

  private func write(_ records: [SharedTextRecord]) throws {
    let data = try JSONEncoder().encode(records)
    #if os(iOS)
    try data.write(to: queueURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #else
    try data.write(to: queueURL, options: .atomic)
    #endif
  }

  private func locked<T>(_ body: () throws -> T) throws -> T {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let descriptor = open(directory.appendingPathComponent("queue.lock").path, O_CREAT | O_RDWR, 0o600)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { close(descriptor) }
    while flock(descriptor, LOCK_EX) != 0 {
      if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    defer { flock(descriptor, LOCK_UN) }
    return try body()
  }
}
