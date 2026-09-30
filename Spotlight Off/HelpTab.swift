import SwiftUI

/// Collapsible help topics. Paragraphs use inline Markdown (**bold**, `code`).
struct HelpTab: View {
    @State private var expanded: Set<String> = [HelpTab.topics[0].title]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Help")

                Card {
                    ForEach(Array(Self.topics.enumerated()), id: \.element.title) { index, topic in
                        if index > 0 { RowDivider() }
                        HelpTopicRow(topic: topic, isExpanded: expanded.contains(topic.title)) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if expanded.contains(topic.title) { expanded.remove(topic.title) }
                                else { expanded.insert(topic.title) }
                            }
                        }
                    }
                }

                HStack {
                    Caption("More questions? Open an issue on GitHub.")
                    Button("GitHub Issues") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/titleunknown/Spotlight-Off/issues")!)
                    }
                    .buttonStyle(.link).font(.caption2)
                }
                .padding(.horizontal, 20).padding(.top, 6)

                Spacer(minLength: 20)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Topics

    static let topics: [HelpTopic] = [
        HelpTopic(title: "What Spotlight Off does", icon: "externaldrive.badge.xmark", color: .accentColor, paragraphs: [
            "Whenever you connect an external drive, macOS starts building a Spotlight index on it. Spotlight Off notices the drive, waits a few seconds for it to settle, and turns indexing off with Apple's own `mdutil` tool. No password or admin rights needed — just Full Disk Access.",
            "It also checks drives that are already connected when it starts, so drives plugged in at boot are covered too. Every action is recorded in the Activity Log.",
        ]),
        HelpTopic(title: "Why turn off indexing on external drives?", icon: "questionmark.circle", color: .blue, paragraphs: [
            "Spotlight stores its index in a hidden **.Spotlight-V100** folder on each drive. On a large drive, building it can take hours of disk activity and use hundreds of megabytes to several gigabytes of space.",
            "That activity slows down copies, drains battery, keeps drives spinning, and is a common cause of “The disk wasn't ejected because one or more programs may be using it.” It also writes to drives you might share with cameras, TVs or Windows PCs.",
        ]),
        HelpTopic(title: "What changes when indexing is off", icon: "magnifyingglass", color: .orange, paragraphs: [
            "Files on that drive won't show up in Spotlight, and Finder searches of the drive may find nothing or be much slower. Apps that rely on Spotlight to find files may not see files there.",
            "Nothing else changes: your files, Finder browsing, Quick Look and copying all work as usual. Your Mac's internal drive keeps its index, and Time Machine backup drives are left alone.",
            "Need to search a particular drive? Re-enable indexing on it. See the next topic.",
        ]),
        HelpTopic(title: "Turning Spotlight back on for a drive", icon: "arrow.uturn.backward.circle", color: .green, paragraphs: [
            "In the **Drives** tab, under **Connected Drives**, click **Re-enable** (or use the drive's submenu in the menu bar). Spotlight Off turns indexing back on and remembers the drive, so it stays on every time you connect it. The drive then appears under **Allowed to Index**.",
            "Click **Forget** there, or **Turn Off** next to the connected drive, to let Spotlight Off manage it again.",
            "Drives are remembered by their volume ID, not their name. Reformatting or erasing a drive gives it a new ID, so it's treated as a new drive.",
            "After re-enabling, macOS rebuilds the index in the background, so search results fill in gradually.",
        ]),
        HelpTopic(title: "Remove Spotlight Index", icon: "trash", color: .red, paragraphs: [
            "Turning indexing off stops Spotlight from updating a drive's index, but it doesn't delete the index macOS already built. **Remove Spotlight Index…** deletes that **.Spotlight-V100** folder and tells you how much space was freed.",
            "It's safe: the folder only contains Spotlight's search data, never your files. It's only offered while indexing is off, because otherwise macOS would immediately rebuild it.",
            "Turn on **Also remove the existing Spotlight index** in the Settings tab to do this automatically whenever a drive is processed.",
            "If removal fails, macOS is protecting the folder. That happens on drives that don't ignore ownership. You can remove it in Terminal with `sudo mdutil -X /Volumes/DriveName`.",
        ]),
        HelpTopic(title: "Remove macOS Clutter", icon: "sparkles", color: .purple, paragraphs: [
            "macOS leaves two kinds of hidden files on drives, which show up as junk on Windows PCs, TVs, cameras and car stereos:",
            "**._ files** (“AppleDouble” files) hold extra file information such as Finder tags, custom icons, download quarantine flags and some app data. Drives formatted as exFAT or FAT32 can't store this information directly, so macOS writes it into a matching ._ file.",
            "**.DS_Store files** hold Finder view settings for a folder, such as icon positions, view style and sort order. They're harmless to delete, and Finder recreates them as needed.",
            "**Remove macOS Clutter…** deletes every .DS_Store file on the drive and runs Apple's `dot_clean` tool on the ._ files. On APFS and Mac OS Extended drives, their information is merged back into the real files. On exFAT and FAT32 drives it can't be, so **tags, custom icons and similar information are lost**. This can't be undone, and it can take a while on large drives.",
            "Hidden system folders (.Spotlight-V100, .fseventsd, .Trashes and similar) are skipped.",
        ]),
        HelpTopic(title: "Stopping new .DS_Store files", icon: "doc.badge.gearshape", color: .gray, paragraphs: [
            "The **Stop Finder creating .DS_Store files on external drives** setting turns on Finder's own hidden preference for this. The Terminal equivalent is `defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true`.",
            "Finder only reads it at launch, so click **Relaunch Finder** (or log out and back in) afterwards. It doesn't delete .DS_Store files that already exist; use Remove macOS Clutter for that. Your Mac's internal drive isn't affected.",
        ]),
        HelpTopic(title: "Which drives are handled", icon: "externaldrive", color: .teal, paragraphs: [
            "**Handled:** USB and Thunderbolt drives, card readers, and SD cards in a Mac's built-in slot. Formats include APFS, Mac OS Extended (HFS+), exFAT and FAT32.",
            "**Left alone:** your Mac's internal drive, disk images (.dmg files), Time Machine backup drives, network drives, and any drive you've allowed to index.",
            "NTFS drives (common on Windows) are read-only on macOS, so their indexing setting can't be changed.",
        ]),
        HelpTopic(title: "Full Disk Access", icon: "lock.shield", color: .indigo, paragraphs: [
            "Changing a drive's Spotlight setting normally requires an administrator. Full Disk Access lets Spotlight Off do it without asking for your password each time. Spotlight Off never reads the contents of your files.",
            "If access is missing or later removed, Spotlight Off shows a warning in the menu bar and at the top of the Settings and Drives tabs, and the **Setup** tab links straight to the right place in System Settings.",
        ]),
        HelpTopic(title: "Troubleshooting", icon: "wrench.and.screwdriver", color: .brown, paragraphs: [
            "**“Could not disable indexing”:** check Full Disk Access in the Setup tab. If it was granted before an update, switch it off and on again in System Settings. The Activity Log shows the exact error from `mdutil`.",
            "**“Indexing state unknown”:** some drives and formats don't report a Spotlight state. Spotlight Off still tries to turn indexing off on them.",
            "**A drive wasn't handled:** make sure Spotlight Off is running and check the Activity Log. Drives you've allowed to index, disk images and Time Machine drives are skipped on purpose.",
            "**Pop-ups instead of notifications:** notifications are turned off for Spotlight Off in System Settings. See step 3 in the Setup tab.",
            "**Saved log file:** `~/Library/Logs/Spotlight Off/activity.log`. Include it when reporting a problem.",
        ]),
        HelpTopic(title: "Doing it yourself in Terminal", icon: "terminal", color: .primary, paragraphs: [
            "Check a drive: `mdutil -s /Volumes/DriveName`",
            "Turn indexing off or on: `sudo mdutil -i off /Volumes/DriveName` (or `on`)",
            "Delete a drive's index: `sudo mdutil -X /Volumes/DriveName`",
            "Rebuild an index from scratch, e.g. if search results seem incomplete after re-enabling: `sudo mdutil -E /Volumes/DriveName`",
        ]),
        HelpTopic(title: "Privacy", icon: "hand.raised", color: .green, paragraphs: [
            "Everything happens on your Mac. History and settings are stored locally, and the log is a plain text file you can read or delete.",
            "The only network request is the update check to GitHub, about once a day or when you click Check Now. It sends nothing about you or your drives, and you can turn automatic checks off in the Settings tab.",
        ]),
    ]
}

struct HelpTopic {
    let title: String
    let icon: String
    let color: Color
    let paragraphs: [String]
}

struct HelpTopicRow: View {
    let topic: HelpTopic
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(topic.color.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: topic.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(topic.color)
                    }
                    Text(topic.title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 8)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(topic.paragraphs, id: \.self) { paragraph in
                        Text(LocalizedStringKey(paragraph))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 54).padding(.trailing, 14).padding(.bottom, 12)
            }
        }
    }
}
