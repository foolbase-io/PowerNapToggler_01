//
//  ContentView.swift
//  PowerNapToggler
//
//  Created by Alon on 19/06/2025.
//

import SwiftUI
import Cocoa
import ServiceManagement

enum PowerState {
    case on, off
}

@main
struct NapTogglerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() } // No window
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    let statusMenu = NSMenu()
    let popover = NSPopover() // make this persistent

    func showStatusPopover(message: String) {
        guard let button = statusItem?.button else {
            print("❌ No status item button")
            return
        }

        let label = NSTextField(labelWithString: message)
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.sizeToFit()

        let vc = NSViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        label.frame.origin = NSPoint(x: 10, y: 5)
        vc.view.addSubview(label)

        popover.contentViewController = vc
        popover.behavior = .transient

        DispatchQueue.main.async {
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.popover.performClose(nil)
            }
        }
    }
    
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = getStatusText()
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Right-click menu
        statusMenu.addItem(
            withTitle: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
    }
    @objc func toggleSettings() {
        print("✅ Menu bar icon clicked")
        let message = NapManager.shared.toggleAll()
        self.showStatusPopover(message: message)

        if let button = statusItem?.button {
            button.title = getStatusText()
        }
    }

    func getStatusText() -> String {
        NapManager.shared.currentPowerNapState() == .on ? "🔆" : "💤"
    }
    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            statusItem?.menu = statusMenu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            toggleSettings()
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

class NapManager {
    static let shared = NapManager()
    private init() {}

    func toggleAll() -> String {
        let currentPN = self.currentPowerNapState()
        let newPN = currentPN == .on ? "0" : "1"

        let currentTCP = self.currentTCPKeepaliveState()
        let newTCP = currentTCP == .on ? "0" : "1"

        let command = """
        pmset -a powernap \(newPN); sysctl -w net.inet.tcp.always_keepalive=\(newTCP)
        """
        self.runCommand(command, requiresSudo: true)

        // Return mode status for UI
        return (newPN == "0" && newTCP == "0") ? "✅ Saving Battery" : "☀️ Normal Mode"
    }

    func togglePowerNap() {
        let current = currentPowerNapState()
        let newState = current == .on ? PowerState.off : PowerState.on
        print("💡 PowerNap state: \(current) → \(newState)")
        runCommand("pmset -a powernap \(newState == .on ? "1" : "0")", requiresSudo: true)
    }

    func currentPowerNapState() -> PowerState {
        let output = shellOutput(command: "pmset -g | grep powernap")
        return output.contains("1") ? .on : .off
    }

    func toggleTCPKeepalive() {
        let current = currentTCPKeepaliveState()
        let newState = current == .on ? PowerState.off : PowerState.on
        print("🌐 TCP Keepalive: \(current) → \(newState)")
        runCommand("sysctl -w net.inet.tcp.always_keepalive=\(newState == .on ? "1" : "0")", requiresSudo: true)
    }

    func currentTCPKeepaliveState() -> PowerState {
        let output = shellOutput(command: "sysctl net.inet.tcp.always_keepalive")
        return output.contains("1") ? .on : .off
    }

    func runCommand(_ command: String, requiresSudo: Bool = false) {
        if requiresSudo {
            let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
            _ = "PowerNapT needs your password to manage energy settings and keep your Mac asleep or awake as needed."
            let script = "do shell script \"\(escaped)\" with administrator privileges with prompt \"PowerNapToggler needs your password to adjust system sleep settings.\""
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            task.launch()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("📤 osascript output:", output)
            }
        } else {
            _ = shellOutput(command: command)
        }
    }

    func shellOutput(command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
