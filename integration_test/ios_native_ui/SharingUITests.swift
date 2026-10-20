import XCTest

/// Runs against the installed debug app and the simulator's Safari.
/// No login credentials or production account are required.
final class SharingUITests: XCTestCase {
  func testImageAndFileBatch() throws {
    continueAfterFailure = false
    let id = UUID().uuidString.lowercased()
    print("SHARE_BATCH_ID=\(id)")
    let source = XCUIApplication(bundleIdentifier: "com.github.gemsnote.SharingFixture")
    source.launchArguments = ["-fixture-id", id]
    source.launch()
    let share = source.buttons["Share image and file"]
    XCTAssertTrue(share.waitForExistence(timeout: 20))
    share.tap()
    let gemsnote = source.staticTexts["Gemsnote"].firstMatch
    XCTAssertTrue(gemsnote.waitForExistence(timeout: 20), source.debugDescription)
    gemsnote.tap()
    let save = source.buttons.matching(NSPredicate(format: "label IN {'保存', 'Save'}")).firstMatch
    XCTAssertTrue(save.waitForExistence(timeout: 20), source.debugDescription)
    expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
    waitForExpectations(timeout: 20)
    let preview = XCTAttachment(screenshot: source.screenshot())
    preview.lifetime = .keepAlways
    add(preview)
    save.tap()
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: save)
    waitForExpectations(timeout: 20)
    XCTAssertFalse(source.alerts.firstMatch.exists, source.debugDescription)
    let app = XCUIApplication(bundleIdentifier: "com.github.gemsnote")
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
  }

  func testSafariShareToGemsnote() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.github.gemsnote")
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    safari.launch()
    XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 30))
    let address = safari.textFields["TabBarItemTitle"]
    XCTAssertTrue(address.waitForExistence(timeout: 20))
    address.tap()
    let url = "http://127.0.0.1:8765/#gemsnote-ui-\(UUID().uuidString.lowercased())"
    print("SHARE_FIXTURE_URL=\(url)")
    let input = safari.searchFields.firstMatch.exists
      ? safari.searchFields.firstMatch : safari.textFields.firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 10))
    input.typeText(url + "\n")
    let more = safari.buttons.matching(NSPredicate(format: "label == '更多' OR label == 'More'")).firstMatch
    XCTAssertTrue(more.waitForExistence(timeout: 30))
    more.tap()
    let share = safari.buttons.matching(NSPredicate(format: "label IN {'分享', '共享', 'Share'}")).firstMatch
    if !share.waitForExistence(timeout: 5) { more.tap() }
    XCTAssertTrue(share.waitForExistence(timeout: 10), safari.debugDescription)
    share.tap()
    let gemsnote = safari.staticTexts["Gemsnote"].firstMatch
    XCTAssertTrue(gemsnote.waitForExistence(timeout: 20), safari.debugDescription)
    gemsnote.tap()
    let cancel = safari.buttons.matching(NSPredicate(format: "label IN {'取消', 'Cancel'}")).firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 20), safari.debugDescription)
    cancel.tap()
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: cancel)
    waitForExpectations(timeout: 20)
    // Cancellation must not persist a record. Reopen and save the same URL;
    // the host verifier requires exactly one record after this second attempt.
    if !gemsnote.waitForExistence(timeout: 3) {
      XCTAssertTrue(more.waitForExistence(timeout: 10))
      more.tap()
      XCTAssertTrue(share.waitForExistence(timeout: 10))
      share.tap()
    }
    XCTAssertTrue(gemsnote.waitForExistence(timeout: 20))
    gemsnote.tap()
    let save = safari.buttons.matching(NSPredicate(format: "label IN {'保存', 'Save'}")).firstMatch
    XCTAssertTrue(save.waitForExistence(timeout: 20), safari.debugDescription)
    let enabled = NSPredicate(format: "enabled == true")
    expectation(for: enabled, evaluatedWith: save)
    waitForExpectations(timeout: 20)
    save.tap()
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: save)
    waitForExpectations(timeout: 20)
    XCTAssertFalse(safari.alerts.firstMatch.exists, safari.debugDescription)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
