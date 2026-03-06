import SwiftUI
import AppKit
import UserNotifications

@main
struct SpotlightOffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // This prevents a blank window from opening at launch
        Settings {
            HistoryView(manager: appDelegate.menuManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuManager = MenuBarManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuManager.start()
    }
}

class MenuBarManager: NSObject, ObservableObject {
    var statusItem: NSStatusItem?
    
    @AppStorage("notificationsEnabled") var notificationsEnabled = true
    @AppStorage("historyList") var historyList: String = "" // Stored as comma-separated string

    func start() {
        // 1. Setup Menu Bar Icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "🚫"
        }
        
        setupMenu()
        
        // 2. Request Notifications
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        // 3. Listen for Drives
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(volumeMounted),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
    }

    func setupMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Spotlight Off Active", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Settings/History Window
        let historyItem = NSMenuItem(title: "View History & Settings...", action: #selector(openSettings), keyEquivalent: "s")
        historyItem.target = self
        menu.addItem(historyItem)
        
        // Notification Toggle
        let toggleItem = NSMenuItem(title: "Show Notifications", action: #selector(toggleNotifications), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = notificationsEnabled ? .on : .off
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }

    @objc func openSettings() {
        // This opens the Settings scene defined in the App struct
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleNotifications() {
        notificationsEnabled.toggle()
        setupMenu()
    }

    @objc func volumeMounted(notification: NSNotification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        if devicePath == "/" { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        process.arguments = ["-i", "off", devicePath]
        
        do {
            try process.run()
            let driveName = devicePath.components(separatedBy: "/").last ?? "Unknown Drive"
            addToHistory(name: driveName)
            
            if notificationsEnabled {
                sendNotification(name: driveName)
            }
        } catch {
            print("Failed to disable spotlight")
        }
    }

    func addToHistory(name: String) {
        let current = historyList.components(separatedBy: ",").filter { !$0.isEmpty }
        if !current.contains(name) {
            historyList = (current + [name]).joined(separator: ",")
        }
    }

    func sendNotification(name: String) {
        let content = UNMutableNotificationContent()
        content.title = "Spotlight Disabled"
        content.body = "Indexing turned off for \(name)"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// The Settings / History UI
struct HistoryView: View {
    @ObservedObject var manager: MenuBarManager

    var body: some View {
        VStack(alignment: .leading) {
            Text("Disabled Drives History").font(.headline)
            List {
                let drives = manager.historyList.components(separatedBy: ",").filter { !$0.isEmpty }
                ForEach(drives, id: \.self) { drive in
                    Text(drive)
                }
                .onDelete { indexSet in
                    var current = drives
                    current.remove(atOffsets: indexSet)
                    manager.historyList = current.joined(separator: ",")
                }
            }
            .frame(height: 200)
            
            Toggle("Enable Notifications", isOn: $manager.notificationsEnabled)
                .padding(.top)
        }
        .padding()
        .frame(width: 350)
    }
}
