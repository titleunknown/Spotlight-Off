import AppKit

/// Destructive drive actions, confirmed with the same wording whether they're
/// started from the menu bar or the settings window.
@MainActor
enum DriveActions {
    static func removeSpotlightIndex(_ volume: MountedVolume, monitor: DriveMonitor) {
        guard confirm(
            title: "Remove the Spotlight index from “\(volume.name)”?",
            message: "This deletes the .Spotlight-V100 folder macOS built before indexing was turned off, freeing the space it uses. Indexing stays off.",
            button: "Remove Index")
        else { return }
        monitor.removeSpotlightIndex(volume)
    }

    static func removeClutter(_ volume: MountedVolume, monitor: DriveMonitor) {
        guard confirm(
            title: "Remove macOS clutter from “\(volume.name)”?",
            message: "This deletes .DS_Store files and cleans up “._” files across the whole drive. On exFAT and FAT drives, “._” files hold Finder metadata such as tags and custom icons, and that metadata will be lost. This can't be undone.",
            button: "Remove Clutter")
        else { return }
        monitor.removeClutter(volume)
    }

    private static func confirm(title: String, message: String, button: String) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
