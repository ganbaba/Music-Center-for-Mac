import AppKit
import ApplicationServices

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
func label(_ e: AXUIElement) -> [String] {
    ["AXTitle", "AXDescription", "AXHelp", "AXIdentifier"].compactMap { attribute(e, $0) as? String }
        .filter { !$0.isEmpty }
}
func position(_ e: AXUIElement) -> CGPoint? {
    guard let raw = attribute(e, "AXPosition") else { return nil }
    var p = CGPoint.zero
    return AXValueGetValue(raw as! AXValue, .cgPoint, &p) ? p : nil
}
func dimensions(_ e: AXUIElement) -> CGSize? {
    guard let raw = attribute(e, "AXSize") else { return nil }
    var s = CGSize.zero
    return AXValueGetValue(raw as! AXValue, .cgSize, &s) ? s : nil
}
let arg = CommandLine.arguments
let isATRAC = ProcessInfo.processInfo.environment["MUSIC_CENTER_QA_KIND"] == "atrac"
let targetBundle = isATRAC ? "local.musiccenter.uirecreation.atracqa" : "local.musiccenter.uirecreation.wizardsqa"
let targetTitle = isATRAC ? "Music Center ATRAC QA" : "Music Center Wizards QA"
guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundle).first else { exit(2) }
let pid = running.processIdentifier
let app = AXUIElementCreateApplication(pid)
if arg.count > 1, arg[1] == "quit" { running.terminate(); exit(0) }
guard let windows = attribute(app, "AXWindows") as? [AXUIElement],
      let win = windows.first(where: { label($0).contains(targetTitle) }),
      let origin = position(win), let winSize = dimensions(win) else { exit(3) }

func all(_ node: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    if depth > 13 { return [] }
    let children = attribute(node, "AXChildren") as? [AXUIElement] ?? []
    return [node] + children.flatMap { all($0, depth: depth + 1) }
}
let cmd = arg[1]
if cmd == "activate" {
    running.activate(options: [.activateAllWindows])
    AXUIElementPerformAction(win, kAXRaiseAction as CFString)
    Thread.sleep(forTimeInterval: 0.4)
    exit(0)
}
if cmd == "list" || cmd == "find" {
    print("window", origin, winSize)
    for node in windows.flatMap({ all($0) }) {
        let title = label(node)
        let role = attribute(node, "AXRole") as? String ?? "?"
        if cmd == "list" && !["AXButton","AXMenuItem","AXTextField","AXTextArea","AXCheckBox","AXSheet","AXWindow"].contains(role) { continue }
        let value = attribute(node, "AXValue") as? String ?? ""
        if cmd == "find" && !title.contains(where: { $0.contains(arg[2]) }) && !value.contains(arg[2]) { continue }
        let enabled = attribute(node, "AXEnabled") as? Bool
        print(role, enabled.map { $0 ? "on" : "off" } ?? "-", title.joined(separator: " | "), String(value.prefix(180)), position(node) ?? .zero)
    }
    exit(0)
}
if cmd == "focused" || cmd == "set" {
    guard let raw = attribute(app, "AXFocusedUIElement") else { exit(10) }
    let field = raw as! AXUIElement
    let role = attribute(field, "AXRole") as? String ?? "?"
    print(role, label(field).joined(separator: " | "), attribute(field, "AXValue") as? String ?? "", position(field) ?? .zero)
    if cmd == "set" {
        guard ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) else { exit(10) }
        let result = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, arg[2] as CFString)
        print("set", result.rawValue)
        guard result == .success else { exit(11) }
    }
    exit(0)
}
if cmd == "panel" {
    guard let node = all(win).first(where: { label($0).contains(arg[2]) }),
          let p = position(node), let s = dimensions(node) else { exit(15) }
    print(p.x-origin.x, p.y-origin.y, s.width, s.height, winSize.width)
    exit(0)
}
if cmd == "fill" {
    guard let node = all(win).first(where: {
        let role = attribute($0, "AXRole") as? String ?? ""
        return ["AXTextField", "AXTextArea"].contains(role) && label($0).contains(arg[2])
    }) else { exit(16) }
    AXUIElementSetAttributeValue(node, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    guard AXUIElementSetAttributeValue(node, kAXValueAttribute as CFString, arg[3] as CFString) == .success else { exit(17) }
    Thread.sleep(forTimeInterval: 0.2)
    exit(0)
}
if cmd == "window" {
    for item in CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String:Any]] ?? []
    where item[kCGWindowOwnerPID as String] as? Int32 == pid && item[kCGWindowLayer as String] as? Int == 0 {
        if let number = item[kCGWindowNumber as String], (item[kCGWindowName as String] as? String) == targetTitle {
            print(number)
            exit(0)
        }
    }
    exit(4)
}
if !running.isActive {
    running.activate()
    Thread.sleep(forTimeInterval: 0.35)
    if !running.isActive { exit(5) }
}
if cmd == "press" {
    let nodes = windows.flatMap { all($0) }
    let matches = nodes.filter { label($0).contains(arg[2]) && (attribute($0, "AXEnabled") as? Bool) != false }
    guard let node = matches.first(where: { ["AXButton","AXMenuItem","AXCheckBox"].contains(attribute($0, "AXRole") as? String ?? "") }),
          AXUIElementPerformAction(node, kAXPressAction as CFString) == .success else { exit(6) }
 } else if cmd == "key" {
    guard let code = UInt16(arg[2]), let flagValue = UInt64(arg[3]) else { exit(7) }
    for down in [true, false] {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { exit(5) }
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = CGEventFlags(rawValue: flagValue)
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
    }
} else if cmd == "text" {
    for character in arg[2] {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { exit(5) }
        let utf16 = Array(String(character).utf16)
        let press = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        utf16.withUnsafeBufferPointer { press.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: $0.baseAddress) }
        press.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.008)
    }
 } else if cmd == "hit" {
    let matches = windows.flatMap { all($0) }.filter {
        let value = attribute($0, "AXValue") as? String
        return value == arg[2] && (attribute($0, "AXRole") as? String) == "AXTextField"
    }
    guard let match = matches.first, let p = position(match), let s = dimensions(match),
          s.height > 0, s.width > 0, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { exit(12) }
    let point = CGPoint(x: p.x + min(s.width / 2, 30), y: p.y + s.height / 2)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
    }
} else if cmd == "click" || cmd == "move" {
    guard let x = Double(arg[2]), let y = Double(arg[3]), x >= 0, y >= 0, x < winSize.width, y < winSize.height else { exit(8) }
    let point = CGPoint(x: origin.x + x, y: origin.y + y)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    if cmd == "click" {
        Thread.sleep(forTimeInterval: 0.08)
        guard running.isActive else { exit(5) }
        for t in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.06)
        }
    }
} else { exit(9) }
Thread.sleep(forTimeInterval: 0.28)
