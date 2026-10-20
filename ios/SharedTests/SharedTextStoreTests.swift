import Foundation

// Runs against the same Foundation storage source used in both iOS targets.
// No iOS SDK or third-party test framework is required for these storage tests.
@main
struct SharedTextStoreTests {
  static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw SharedTextStore.Failure("FAIL: \(message)") }
  }

  static func rejects(_ message: String, _ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw SharedTextStore.Failure("FAIL: expected rejection: \(message)")
  }

  static func record(_ number: Int, text: String = "分享正文") -> SharedTextRecord {
    SharedTextRecord(id: String(format: "%024x", number), title: "标题", text: text)
  }

  static func main() throws {
    if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "enqueue" {
      let directory = URL(fileURLWithPath: CommandLine.arguments[2])
      try SharedTextStore(directory: directory).enqueue(record(Int(CommandLine.arguments[3])!))
      return
    }
    try check(NativeLanguage.isChinese(preference: "system", languages: ["zh-Hant-TW"]),
      "system Chinese variants")
    try check(!NativeLanguage.isChinese(preference: "system", languages: ["fr", "zh"]),
      "other system languages use English")
    try check(NativeLanguage.isChinese(preference: "zh", languages: ["en"]),
      "explicit Chinese")
    try check(!NativeLanguage.isChinese(preference: "en", languages: ["zh"]),
      "explicit English")
    print("PASS native language selection")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("basic")
    let store = SharedTextStore(directory: directory)
    try check(store.peek() == nil, "empty inbox")
    let first = record(1)
    try store.enqueue(first)
    try store.enqueue(first)
    try check(SharedTextStore(directory: directory).peek() == first, "durable, non-consuming peek")
    try rejects("same ID changed content") { try store.enqueue(record(1, text: "changed")) }
    try rejects("empty claim") { try store.claim(id: first.id, accountKey: "") }
    try rejects("missing claim") { try store.claim(id: record(2).id, accountKey: "A") }
    try store.claim(id: first.id, accountKey: "server-A/user")
    try store.claim(id: first.id, accountKey: "server-A/user")
    try rejects("cross-account claim") { try store.claim(id: first.id, accountKey: "server-B/user") }
    try store.enqueue(first)
    try check(store.peek()?.accountKey == "server-A/user", "enqueue retry preserves claimed account")
    try store.acknowledge(id: record(2).id)
    try check(store.peek()?.id == first.id, "unknown acknowledgement does not remove other entries")
    try store.acknowledge(id: first.id)
    try store.acknowledge(id: first.id)
    try check(store.peek() == nil, "idempotent acknowledgement; only one retry record")
    print("PASS persistence, claim isolation, idempotence")

    let payload = Data([1, 2, 3, 4])
    var image = record(10, text: "photo.png")
    image.resourceKind = "image"
    image.resourceName = "photo.png"
    image.resourceSize = payload.count
    try store.enqueueBatch([(first, nil), (image, payload)])
    try store.acknowledge(id: first.id)
    try check(store.peek() == image, "batch preserves FIFO metadata")
    try rejects("unclaimed original") { _ = try store.readResource(id: image.id, accountKey: "A") }
    try store.claim(id: image.id, accountKey: "A")
    try check(store.readResource(id: image.id, accountKey: "A") == payload, "durable original")
    try rejects("other account original") { _ = try store.readResource(id: image.id, accountKey: "B") }
    try store.enqueueBatch([(image, payload)])
    try rejects("different original retry") {
      try store.enqueueBatch([(image, Data([4, 3, 2, 1]))])
    }
    try store.acknowledge(id: image.id)
    try check(!FileManager.default.fileExists(
      atPath: directory.appendingPathComponent(image.id + ".resource").path), "ack cleans original")
    try rejects("bad batch leaves no prefix") {
      try store.enqueueBatch([(first, nil), (image, Data([1]))])
    }
    try check(store.peek() == nil, "failed batch is invisible")
    var unsafe = image
    unsafe.resourceName = "../photo.png"
    try rejects("unsafe filename") { try store.enqueueBatch([(unsafe, payload)]) }
    for index in 1...7 { try store.enqueue(record(index)) }
    try rejects("capacity rejects whole batch") {
      try store.enqueueBatch([(image, payload), (record(11), nil)])
    }
    for index in 1...7 { try store.acknowledge(id: record(index).id) }
    try check(store.peek() == nil, "capacity failure left no partial entries")
    print("PASS resource persistence, account isolation, atomic batch, cleanup")

    for text in ["", " \n", "\u{FEFF}\u{85}\u{A0}", "nul\0", String(repeating: "中", count: 90_000)] {
      try rejects("invalid content") { try store.enqueue(record(1, text: text)) }
    }
    try rejects("invalid ID") {
      try store.enqueue(SharedTextRecord(id: "invalid", title: "", text: "text"))
    }
    try rejects("oversized title") {
      try store.enqueue(SharedTextRecord(id: first.id, title: String(repeating: "x", count: 201), text: "text"))
    }
    try rejects("pre-bound account") {
      try store.enqueue(SharedTextRecord(id: first.id, title: "", text: "text", accountKey: "A"))
    }
    let combiningTitle = "a" + String(repeating: "\u{301}", count: 5000)
    try check(combiningTitle.count == 1, "combining character fixture")
    try rejects("one grapheme cannot bypass title byte limit") {
      try store.enqueue(SharedTextRecord(id: first.id, title: combiningTitle, text: "text"))
    }
    // Max-size control characters expand sixfold in JSON, still fit the disk bound.
    let escaped = String(repeating: "\u{1}", count: 256 * 1024)
    for index in 1...8 { try store.enqueue(record(index, text: escaped)) }
    try rejects("inbox full") { try store.enqueue(record(9)) }
    for index in 1...8 {
      try check(store.peek()?.id == record(index).id, "FIFO order")
      try store.acknowledge(id: record(index).id)
    }
    print("PASS input/byte limits, bounded queue, FIFO")

    let damaged = Data("not-json".utf8)
    let file = directory.appendingPathComponent("queue.json")
    try damaged.write(to: file)
    try rejects("corrupt peek") { _ = try store.peek() }
    try rejects("corrupt enqueue") { try store.enqueue(first) }
    try rejects("corrupt acknowledge") { try store.acknowledge(id: first.id) }
    try check(Data(contentsOf: file) == damaged, "corruption never silently replaces queued data")
    try JSONEncoder().encode([first, first]).write(to: file)
    try rejects("duplicate IDs on disk") { _ = try store.peek() }
    try Data(repeating: 0, count: 16 * 1024 * 1024 + 1).write(to: file)
    try rejects("oversized disk data") { _ = try store.peek() }
    print("PASS corrupt and oversized storage protection")

    // Independent OS processes exercise the app/extension locking boundary.
    let parallelDirectory = root.appendingPathComponent("parallel")
    let children = try (1...8).map { index -> Process in
      let child = Process()
      child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
      child.arguments = ["enqueue", parallelDirectory.path, String(index)]
      try child.run()
      return child
    }
    for child in children {
      child.waitUntilExit()
      try check(child.terminationStatus == 0, "child enqueue")
    }
    let parallel = SharedTextStore(directory: parallelDirectory)
    var ids = Set<String>()
    while let entry = try parallel.peek() {
      ids.insert(entry.id)
      try parallel.acknowledge(id: entry.id)
    }
    try check(ids == Set((1...8).map { record($0).id }), "no lost concurrent writes")
    print("PASS cross-process concurrent writes; all storage tests passed")
  }
}
