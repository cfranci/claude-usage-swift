import Cocoa

// MARK: - Constants

let appVersion = "2.1.34"

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let isoFormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()

// MARK: - Usage API

struct UsageResponse: Codable {
    let five_hour: UsageLimit?
    let seven_day: UsageLimit?
    let seven_day_opus: UsageLimit?
    let seven_day_sonnet: UsageLimit?
    let seven_day_oauth_apps: UsageLimit?
    let seven_day_cowork: UsageLimit?
    let extra_usage: ExtraUsage?
}

func detectModel(_ usage: UsageResponse) -> String {
    if let opus = usage.seven_day_opus, opus.utilization > 0 { return "opus" }
    if let sonnet = usage.seven_day_sonnet, sonnet.utilization > 0 { return "sonnet" }
    return "opus"
}

struct UsageLimit: Codable {
    let utilization: Double
    let resets_at: String?
}

struct ExtraUsage: Codable {
    let is_enabled: Bool
    let monthly_limit: Double?
    let used_credits: Double?
    let utilization: Double?
}

// All trackable usage categories
let allCategoryKeys: [String] = [
    "five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet",
    "seven_day_oauth_apps", "seven_day_cowork", "extra_usage"
]
let categoryLabels: [String: String] = [
    "five_hour": "5-hour",
    "seven_day": "Weekly",
    "seven_day_opus": "Opus",
    "seven_day_sonnet": "Sonnet",
    "seven_day_oauth_apps": "OAuth Apps",
    "seven_day_cowork": "Cowork",
    "extra_usage": "Extra"
]
let defaultPinnedKeys: Set<String> = ["five_hour", "seven_day", "seven_day_sonnet", "extra_usage"]

func getOAuthToken() -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let jsonData = json.data(using: .utf8),
              let creds = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let oauth = creds["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }
        return token
    } catch {
        return nil
    }
}

func fetchUsage(token: String, completion: @escaping (UsageResponse?) -> Void) {
    guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
        completion(nil)
        return
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    request.setValue("claude-code/\(appVersion)", forHTTPHeaderField: "User-Agent")

    let session = URLSession(configuration: .ephemeral)
    session.dataTask(with: request) { data, _, _ in
        guard let data = data,
              let usage = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
            completion(nil)
            return
        }
        completion(usage)
    }.resume()
}

func formatReset(_ isoString: String) -> String {
    if let date = isoFormatter.date(from: isoString) {
        return formatResetDate(date)
    }
    if let date = isoFormatterNoFrac.date(from: isoString) {
        return formatResetDate(date)
    }
    return "?"
}

func formatResetDate(_ date: Date) -> String {
    let diff = date.timeIntervalSince(Date())
    if diff < 0 { return "now" }

    let hours = Int(diff) / 3600
    let mins = (Int(diff) % 3600) / 60

    if hours == 0 {
        return "\(mins)m"
    } else if hours < 24 {
        return "\(hours)h \(mins)m"
    } else {
        return dateFormatter.string(from: date)
    }
}

func formatResetTooltip(_ date: Date) -> String {
    let diff = date.timeIntervalSince(Date())
    if diff < 0 { return "T-0:00" }

    let totalSeconds = Int(diff)
    let hours = totalSeconds / 3600
    let mins = (totalSeconds % 3600) / 60

    return String(format: "T-%d:%02d", hours, mins)
}

func formatResetShort(_ date: Date, showH: Bool = true) -> String {
    let diff = date.timeIntervalSince(Date())
    if diff < 0 { return "now" }

    let hours = diff / 3600
    if hours < 1 {
        return "\(Int(diff) / 60)m"
    }
    let quarters = (hours * 4).rounded() / 4
    let whole = Int(quarters)
    let frac = quarters - Double(whole)
    let fracStr: String
    if frac >= 0.75 { fracStr = "\u{00B3}\u{2044}\u{2084}" }
    else if frac >= 0.5 { fracStr = "\u{00B9}\u{2044}\u{2082}" }
    else if frac >= 0.25 { fracStr = "\u{00B9}\u{2044}\u{2084}" }
    else { fracStr = "" }
    return "\(whole)\(fracStr)\(showH ? "h" : "")"
}

// MARK: - Sound Playback

func playClicks(count: Int, soundName: String, delay: TimeInterval = 0.15, completion: (() -> Void)? = nil) {
    guard count > 0 else {
        completion?()
        return
    }
    if let sound = NSSound(named: NSSound.Name(soundName)) {
        sound.play()
    }
    if count > 1 {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            playClicks(count: count - 1, soundName: soundName, delay: delay, completion: completion)
        }
    } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completion?()
        }
    }
}

func playAlarmBursts(bursts: Int = 3, clicksPerBurst: Int = 5, soundName: String, checkMuted: @escaping () -> Bool, completion: (() -> Void)? = nil) {
    guard bursts > 0 else {
        completion?()
        return
    }
    if checkMuted() {
        completion?()
        return
    }
    playClicks(count: clicksPerBurst, soundName: soundName) {
        if bursts > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playAlarmBursts(bursts: bursts - 1, clicksPerBurst: clicksPerBurst, soundName: soundName, checkMuted: checkMuted, completion: completion)
            }
        } else {
            completion?()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var hoverTimer: Timer?

    // Store state for hover
    var fiveHourResetDate: Date?
    var currentPct: String = "..."
    var isHovering = false
    var isAnimating = false
    var animTimer: Timer?

    // Data-driven usage items: key -> menu item
    var usageItems: [String: NSMenuItem] = [:]
    var updatedItem: NSMenuItem!

    // Which keys are pinned to the main menu
    var menuReady = false
    var suppressRebuild = false
    var needsMenuRebuild = false
    var pinnedKeys: Set<String> = defaultPinnedKeys {
        didSet {
            UserDefaults.standard.set(Array(pinnedKeys), forKey: "pinnedKeys")
            if menuReady && !suppressRebuild { rebuildMenu() }
        }
    }

    // More submenu items for toggling
    var moreToggleItems: [String: NSMenuItem] = [:]
    var moreMenu: NSMenu!

    // Refresh interval items
    var interval1mItem: NSMenuItem!
    var interval5mItem: NSMenuItem!
    var interval30mItem: NSMenuItem!
    var interval1hItem: NSMenuItem!

    // Notification menu items
    var alert100Item: NSMenuItem!
    var alertLimitItem: NSMenuItem!
    var alarmAfter100Item: NSMenuItem!
    var alarmAfterUsedItem: NSMenuItem!
    var alarmAfterAnyItem: NSMenuItem!
    var alarmOffItem: NSMenuItem!
    var alarmSkipItem: NSMenuItem!

    // Sound menu items
    var soundItems: [NSMenuItem] = []

    // Reset info display mode: 0=hover only, 1=auto
    var resetInfoMode: Int = 0 {
        didSet {
            UserDefaults.standard.set(resetInfoMode, forKey: "resetInfoMode")
            updateResetInfoMenu()
            scheduleAutoShow()
        }
    }
    var autoShowDelay: TimeInterval = 1.0 {
        didSet {
            UserDefaults.standard.set(autoShowDelay, forKey: "autoShowDelay")
            updateResetInfoMenu()
            scheduleAutoShow()
        }
    }
    var autoShowTimer: Timer?
    var isAutoShowing = false
    var autoShowingReset = false

    // Whether to show the "h" suffix on reset time (e.g. "3½h" vs "3½")
    var showHourSuffix: Bool = true {
        didSet {
            UserDefaults.standard.set(showHourSuffix, forKey: "showHourSuffix")
            updateResetInfoMenu()
        }
    }
    var showHourSuffixItem: NSMenuItem!

    // Reset info menu items
    var resetInfoHoverItem: NSMenuItem!
    var resetInfoAutoItem: NSMenuItem!
    var delayItems: [NSMenuItem] = []

    // Current interval in seconds
    var refreshInterval: TimeInterval = 300 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            updateIntervalMenu()
            restartTimer()
        }
    }

    // Notification preferences
    var alert100Enabled: Bool = true {
        didSet { UserDefaults.standard.set(alert100Enabled, forKey: "alert100Enabled") }
    }
    var alertLimitEnabled: Bool = true {
        didSet { UserDefaults.standard.set(alertLimitEnabled, forKey: "alertLimitEnabled") }
    }
    // 0=Off, 1=After 100%, 2=After any used, 3=After any session
    var alarmCondition: Int = 0 {
        didSet {
            UserDefaults.standard.set(alarmCondition, forKey: "alarmCondition")
            updateAlarmMenu()
        }
    }
    var alarmSkipIfPrevZero: Bool = false {
        didSet { UserDefaults.standard.set(alarmSkipIfPrevZero, forKey: "alarmSkipIfPrevZero") }
    }
    var selectedSoundName: String = "Tink" {
        didSet {
            UserDefaults.standard.set(selectedSoundName, forKey: "selectedSoundName")
            updateSoundMenu()
        }
    }

    // Transition tracking
    var previousFiveHourUtil: Double = -1
    var previousExtraUtil: Double = -1
    var lastKnownResetDate: Date?
    var lastSessionFinalUtil: Double = 0
    var previousSessionHadUsage: Bool = false
    var alarmIsPlaying: Bool = false
    var alarmCheckTimer: Timer?
    var lastFetchDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Load saved preferences
        let ud = UserDefaults.standard
        let savedInterval = ud.double(forKey: "refreshInterval")
        if savedInterval > 0 { refreshInterval = savedInterval }

        if ud.object(forKey: "alert100Enabled") != nil {
            alert100Enabled = ud.object(forKey: "alert100Enabled") as? Bool ?? true
        }
        if ud.object(forKey: "alertLimitEnabled") != nil {
            alertLimitEnabled = ud.object(forKey: "alertLimitEnabled") as? Bool ?? true
        }
        alarmCondition = ud.object(forKey: "alarmCondition") as? Int ?? 0
        if ud.object(forKey: "alarmSkipIfPrevZero") != nil {
            alarmSkipIfPrevZero = ud.object(forKey: "alarmSkipIfPrevZero") as? Bool ?? false
        }
        selectedSoundName = ud.object(forKey: "selectedSoundName") as? String ?? "Tink"
        resetInfoMode = ud.object(forKey: "resetInfoMode") as? Int ?? 0
        let savedDelay = ud.double(forKey: "autoShowDelay")
        if savedDelay > 0 { autoShowDelay = savedDelay }
        if ud.object(forKey: "showHourSuffix") != nil {
            showHourSuffix = ud.bool(forKey: "showHourSuffix")
        }

        if let saved = ud.object(forKey: "pinnedKeys") as? [String] {
            pinnedKeys = Set(saved)
        }

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "..."

        // Create usage menu items for all categories
        for key in allCategoryKeys {
            let label = categoryLabels[key] ?? key
            let item = NSMenuItem(title: "\(label): ...", action: nil, keyEquivalent: "")
            usageItems[key] = item
        }
        updatedItem = NSMenuItem(title: "Updated: --", action: nil, keyEquivalent: "")

        // Build the full menu
        menu = NSMenu()
        buildMenu()
        menuReady = true

        // Don't set statusItem.menu — handle click manually so hover tracking works
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Update checkmarks
        updateIntervalMenu()
        updateNotificationMenu()
        updateAlarmMenu()
        updateSoundMenu()
        updateResetInfoMenu()

        // Initial fetch
        refresh()

        // Start timer
        restartTimer()

        // Poll mouse position to detect hover over status item
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkHover()
        }
        hoverTimer?.tolerance = 0.1

        // Subscribe to sleep/wake notifications
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleSleep), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleWake), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    // MARK: - Menu Building

    func buildMenu() {
        menu.removeAllItems()

        // Pinned usage items (in canonical order)
        for key in allCategoryKeys {
            if pinnedKeys.contains(key), let item = usageItems[key] {
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(updatedItem)

        let copyItem = NSMenuItem(title: "Copy Usage", action: #selector(copyUsage), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem.separator())

        // Refresh Interval submenu
        let intervalMenu = NSMenu()
        interval1mItem = NSMenuItem(title: "Every 1 minute", action: #selector(setInterval1m), keyEquivalent: "")
        interval5mItem = NSMenuItem(title: "Every 5 minutes", action: #selector(setInterval5m), keyEquivalent: "")
        interval30mItem = NSMenuItem(title: "Every 30 minutes", action: #selector(setInterval30m), keyEquivalent: "")
        interval1hItem = NSMenuItem(title: "Every hour", action: #selector(setInterval1h), keyEquivalent: "")
        interval1mItem.target = self
        interval5mItem.target = self
        interval30mItem.target = self
        interval1hItem.target = self
        intervalMenu.addItem(interval1mItem)
        intervalMenu.addItem(interval5mItem)
        intervalMenu.addItem(interval30mItem)
        intervalMenu.addItem(interval1hItem)
        let intervalItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        // Reset Info submenu
        let resetInfoMenu = NSMenu()
        resetInfoHoverItem = NSMenuItem(title: "Hover", action: #selector(setResetInfoHover), keyEquivalent: "")
        resetInfoHoverItem.target = self
        resetInfoAutoItem = NSMenuItem(title: "Auto", action: #selector(setResetInfoAuto), keyEquivalent: "")
        resetInfoAutoItem.target = self
        resetInfoMenu.addItem(resetInfoHoverItem)
        resetInfoMenu.addItem(resetInfoAutoItem)
        resetInfoMenu.addItem(NSMenuItem.separator())

        delayItems.removeAll()
        let delays: [(String, TimeInterval)] = [("0.25s", 0.25), ("0.5s", 0.5), ("1s", 1.0), ("2s", 2.0)]
        for (label, delay) in delays {
            let item = NSMenuItem(title: label, action: #selector(selectDelay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = delay as NSNumber
            resetInfoMenu.addItem(item)
            delayItems.append(item)
        }
        resetInfoMenu.addItem(NSMenuItem.separator())
        showHourSuffixItem = NSMenuItem(title: "Show \"h\"", action: #selector(toggleHourSuffix), keyEquivalent: "")
        showHourSuffixItem.target = self
        resetInfoMenu.addItem(showHourSuffixItem)

        let resetInfoItem = NSMenuItem(title: "Reset Info", action: nil, keyEquivalent: "")
        resetInfoItem.submenu = resetInfoMenu
        menu.addItem(resetInfoItem)

        // Notifications submenu
        let notifMenu = NSMenu()

        alert100Item = NSMenuItem(title: "100% Alert", action: #selector(toggleAlert100), keyEquivalent: "")
        alert100Item.target = self
        notifMenu.addItem(alert100Item)

        alertLimitItem = NSMenuItem(title: "Usage Limit Alert", action: #selector(toggleAlertLimit), keyEquivalent: "")
        alertLimitItem.target = self
        notifMenu.addItem(alertLimitItem)

        notifMenu.addItem(NSMenuItem.separator())

        // Reset Alarm submenu
        let alarmMenu = NSMenu()
        alarmAfter100Item = NSMenuItem(title: "After 100% session", action: #selector(setAlarmAfter100), keyEquivalent: "")
        alarmAfter100Item.target = self
        alarmMenu.addItem(alarmAfter100Item)

        alarmAfterUsedItem = NSMenuItem(title: "After any used session", action: #selector(setAlarmAfterUsed), keyEquivalent: "")
        alarmAfterUsedItem.target = self
        alarmMenu.addItem(alarmAfterUsedItem)

        alarmAfterAnyItem = NSMenuItem(title: "After any session", action: #selector(setAlarmAfterAny), keyEquivalent: "")
        alarmAfterAnyItem.target = self
        alarmMenu.addItem(alarmAfterAnyItem)

        alarmOffItem = NSMenuItem(title: "Off", action: #selector(setAlarmOff), keyEquivalent: "")
        alarmOffItem.target = self
        alarmMenu.addItem(alarmOffItem)

        alarmMenu.addItem(NSMenuItem.separator())

        alarmSkipItem = NSMenuItem(title: "Skip if previous was 0%", action: #selector(toggleAlarmSkip), keyEquivalent: "")
        alarmSkipItem.target = self
        alarmMenu.addItem(alarmSkipItem)

        let alarmItem = NSMenuItem(title: "Reset Alarm", action: nil, keyEquivalent: "")
        alarmItem.submenu = alarmMenu
        notifMenu.addItem(alarmItem)

        notifMenu.addItem(NSMenuItem.separator())

        // Sound submenu
        let soundMenu = NSMenu()
        soundItems.removeAll()
        let soundNames = ["Tink", "Pop", "Purr", "Funk", "Glass", "Ping", "Morse"]
        for name in soundNames {
            let item = NSMenuItem(title: name, action: #selector(selectSound(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            soundMenu.addItem(item)
            soundItems.append(item)
        }
        let soundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        soundItem.submenu = soundMenu
        notifMenu.addItem(soundItem)

        let notifItem = NSMenuItem(title: "Notifications", action: nil, keyEquivalent: "")
        notifItem.submenu = notifMenu
        menu.addItem(notifItem)

        // More submenu — all categories with checkmark = pinned
        moreMenu = NSMenu()
        moreToggleItems.removeAll()
        for key in allCategoryKeys {
            let label = categoryLabels[key] ?? key
            let item = NSMenuItem(title: label, action: #selector(togglePin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = pinnedKeys.contains(key) ? .on : .off
            moreMenu.addItem(item)
            moreToggleItems[key] = item
        }
        let moreItem = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        moreItem.submenu = moreMenu
        menu.addItem(moreItem)

        // Help submenu
        let helpMenu = NSMenu()

        let claudeUsageItem = NSMenuItem(title: "Claude Usage", action: #selector(openClaudeUsage), keyEquivalent: "")
        claudeUsageItem.target = self
        helpMenu.addItem(claudeUsageItem)

        let apiUsageItem = NSMenuItem(title: "API Usage", action: #selector(openAPIUsage), keyEquivalent: "")
        apiUsageItem.target = self
        helpMenu.addItem(apiUsageItem)

        let githubItem = NSMenuItem(title: "GitHub", action: #selector(openGitHub), keyEquivalent: "")
        githubItem.target = self
        helpMenu.addItem(githubItem)

        helpMenu.addItem(NSMenuItem.separator())

        let shareItem = NSMenuItem(title: "Share...", action: #selector(shareApp), keyEquivalent: "")
        shareItem.target = self
        helpMenu.addItem(shareItem)

        helpMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        helpMenu.addItem(quitItem)

        let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        menu.addItem(helpMenuItem)

        // Restore checkmark states
        updateIntervalMenu()
        updateNotificationMenu()
        updateAlarmMenu()
        updateSoundMenu()
        updateResetInfoMenu()
    }

    func rebuildMenu() {
        buildMenu()
    }

    // MARK: - Sleep/Wake

    @objc func handleSleep() {
        timer?.invalidate()
        timer = nil
        hoverTimer?.invalidate()
        hoverTimer = nil
        alarmCheckTimer?.invalidate()
        alarmCheckTimer = nil
        autoShowTimer?.invalidate()
        autoShowTimer = nil
    }

    @objc func handleWake() {
        restartTimer()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkHover()
        }
        hoverTimer?.tolerance = 0.1
        refresh()
    }

    // MARK: - Hover

    func checkHover() {
        guard let button = statusItem.button,
              let window = button.window else { return }

        let mouseLocation = NSEvent.mouseLocation
        let buttonScreenFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let wasHovering = isHovering
        isHovering = buttonScreenFrame.contains(mouseLocation)

        if isHovering && !wasHovering && !isAnimating {
            guard let resetDate = fiveHourResetDate else { return }
            var target = previousFiveHourUtil >= 100
                ? formatResetTooltip(resetDate)
                : formatResetShort(resetDate, showH: showHourSuffix)
            if alarmCondition != 0 { target += "!" }
            animateTitle(to: target)
        } else if !isHovering && wasHovering && !isAnimating {
            animateTitle(to: currentPct)
        } else if isHovering && !isAnimating {
            guard let resetDate = fiveHourResetDate else { return }
            var title = previousFiveHourUtil >= 100
                ? formatResetTooltip(resetDate)
                : formatResetShort(resetDate, showH: showHourSuffix)
            if alarmCondition != 0 { title += "!" }
            statusItem.button?.title = title
        }
    }

    func animateTitle(to newText: String) {
        isAnimating = true
        animTimer?.invalidate()

        let currentText = statusItem.button?.title ?? ""
        var chars = Array(currentText)
        var step = 0
        let newChars = Array(newText)
        let deleteCount = chars.count
        let totalSteps = deleteCount + newChars.count

        animTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            if step < deleteCount {
                chars.removeLast()
                self.statusItem.button?.title = chars.isEmpty ? " " : String(chars)
            } else {
                let typeIndex = step - deleteCount
                if typeIndex < newChars.count {
                    let partial = String(newChars[0...typeIndex])
                    self.statusItem.button?.title = partial
                }
            }

            step += 1
            if step >= totalSteps {
                timer.invalidate()
                self.statusItem.button?.title = newText
                self.isAnimating = false
            }
        }
    }

    // MARK: - Menu Updates

    func updateIntervalMenu() {
        interval1mItem?.state = refreshInterval == 60 ? .on : .off
        interval5mItem?.state = refreshInterval == 300 ? .on : .off
        interval30mItem?.state = refreshInterval == 1800 ? .on : .off
        interval1hItem?.state = refreshInterval == 3600 ? .on : .off
    }

    func updateNotificationMenu() {
        alert100Item?.state = alert100Enabled ? .on : .off
        alertLimitItem?.state = alertLimitEnabled ? .on : .off
    }

    func updateAlarmMenu() {
        alarmAfter100Item?.state = alarmCondition == 1 ? .on : .off
        alarmAfterUsedItem?.state = alarmCondition == 2 ? .on : .off
        alarmAfterAnyItem?.state = alarmCondition == 3 ? .on : .off
        alarmOffItem?.state = alarmCondition == 0 ? .on : .off
        alarmSkipItem?.state = alarmSkipIfPrevZero ? .on : .off
    }

    func updateSoundMenu() {
        for item in soundItems {
            if let name = item.representedObject as? String {
                item.state = name == selectedSoundName ? .on : .off
            }
        }
    }

    func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = max(10, refreshInterval * 0.1)
    }

    // MARK: - Actions

    @objc func statusItemClicked() {
        if needsMenuRebuild {
            rebuildMenu()
            needsMenuRebuild = false
        }
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc func setInterval1m() { refreshInterval = 60 }
    @objc func setInterval5m() { refreshInterval = 300 }
    @objc func setInterval30m() { refreshInterval = 1800 }
    @objc func setInterval1h() { refreshInterval = 3600 }

    @objc func toggleAlert100() {
        alert100Enabled = !alert100Enabled
        updateNotificationMenu()
    }

    @objc func toggleAlertLimit() {
        alertLimitEnabled = !alertLimitEnabled
        updateNotificationMenu()
    }

    @objc func setAlarmAfter100() { alarmCondition = 1 }
    @objc func setAlarmAfterUsed() { alarmCondition = 2 }
    @objc func setAlarmAfterAny() { alarmCondition = 3 }
    @objc func setAlarmOff() { alarmCondition = 0 }

    @objc func toggleAlarmSkip() {
        alarmSkipIfPrevZero = !alarmSkipIfPrevZero
        updateAlarmMenu()
    }

    @objc func selectSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        selectedSoundName = name
        playClicks(count: 2, soundName: name)
    }

    @objc func setResetInfoHover() { resetInfoMode = 0 }
    @objc func setResetInfoAuto() { resetInfoMode = 1 }
    @objc func toggleHourSuffix() { showHourSuffix = !showHourSuffix }

    @objc func selectDelay(_ sender: NSMenuItem) {
        guard let delay = sender.representedObject as? NSNumber else { return }
        autoShowDelay = delay.doubleValue
    }

    func updateResetInfoMenu() {
        resetInfoHoverItem?.state = resetInfoMode == 0 ? .on : .off
        resetInfoAutoItem?.state = resetInfoMode == 1 ? .on : .off
        for item in delayItems {
            if let delay = item.representedObject as? NSNumber {
                item.state = abs(delay.doubleValue - autoShowDelay) < 0.01 ? .on : .off
            }
        }
        showHourSuffixItem?.state = showHourSuffix ? .on : .off
    }

    func scheduleAutoShow() {
        autoShowTimer?.invalidate()
        autoShowTimer = nil
        isAutoShowing = false
        autoShowingReset = false

        guard resetInfoMode == 1, fiveHourResetDate != nil else { return }

        startAutoRotation()
    }

    func startAutoRotation() {
        autoShowTimer?.invalidate()

        // Determine what to show next
        let showReset = !autoShowingReset
        let delay = autoShowDelay

        autoShowTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, self.resetInfoMode == 1 else { return }
            guard !self.isHovering, !self.isAnimating else {
                // Retry shortly if hovering or animating
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.startAutoRotation() }
                return
            }

            if showReset {
                guard let resetDate = self.fiveHourResetDate else { return }
                self.isAutoShowing = true
                self.autoShowingReset = true
                let target: String
                if self.previousFiveHourUtil >= 100 {
                    target = formatResetTooltip(resetDate)
                } else {
                    target = formatResetShort(resetDate, showH: self.showHourSuffix)
                }
                var display = target
                if self.alarmCondition != 0 { display += "!" }
                self.animateTitle(to: display)
            } else {
                self.isAutoShowing = false
                self.autoShowingReset = false
                self.animateTitle(to: self.currentPct)
            }

            // Schedule the next swap
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.startAutoRotation() }
        }
    }

    @objc func togglePin(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        suppressRebuild = true
        if pinnedKeys.contains(key) {
            pinnedKeys.remove(key)
        } else {
            pinnedKeys.insert(key)
        }
        suppressRebuild = false
        sender.state = pinnedKeys.contains(key) ? .on : .off
        needsMenuRebuild = true
    }

    @objc func openClaudeUsage() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openAPIUsage() {
        if let url = URL(string: "https://platform.claude.com/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openGitHub() {
        if let url = URL(string: "https://github.com/pbnchase/claude-usage-tracker") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func shareApp() {
        guard let button = statusItem.button else { return }
        let text = "Claude Usage Tracker - a macOS menu bar app that tracks your Claude usage limits"
        let url = URL(string: "https://github.com/pbnchase/claude-usage-tracker")!
        let picker = NSSharingServicePicker(items: [text, url])
        picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc func copyUsage() {
        let lines = allCategoryKeys
            .filter { pinnedKeys.contains($0) }
            .compactMap { usageItems[$0]?.title }
        let text = (lines + [updatedItem.title]).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Refresh & Update

    @objc func refresh() {
        statusItem.button?.title = "..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let token = getOAuthToken() else {
                DispatchQueue.main.async {
                    self?.statusItem.button?.title = "?"
                }
                return
            }

            fetchUsage(token: token) { usage in
                DispatchQueue.main.async {
                    self?.updateUI(usage: usage)
                }
            }
        }
    }

    func tabbedMenuItemString(_ label: String, _ detail: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 140, options: [:])]
        let full = "\(label)\t\(detail)"
        return NSAttributedString(string: full, attributes: [
            .paragraphStyle: paragraph,
            .font: NSFont.menuFont(ofSize: 14)
        ])
    }

    func updateUsageItem(key: String, limit: UsageLimit?) {
        guard let item = usageItems[key] else { return }
        let label = categoryLabels[key] ?? key
        if let l = limit {
            let pct = Int(l.utilization)
            let reset = l.resets_at.map { formatReset($0) } ?? "--"
            item.title = "\(label): \(pct)% (resets \(reset))"
            item.attributedTitle = tabbedMenuItemString("\(label): \(pct)%", "resets \(reset)")
        } else {
            item.title = "\(label): --"
            item.attributedTitle = nil
        }
    }

    func updateUI(usage: UsageResponse?) {
        guard let usage = usage else {
            statusItem.button?.title = "?"
            return
        }

        lastFetchDate = Date()

        // Update all limit-based categories
        updateUsageItem(key: "five_hour", limit: usage.five_hour)
        updateUsageItem(key: "seven_day", limit: usage.seven_day)
        updateUsageItem(key: "seven_day_opus", limit: usage.seven_day_opus)
        updateUsageItem(key: "seven_day_sonnet", limit: usage.seven_day_sonnet)
        updateUsageItem(key: "seven_day_oauth_apps", limit: usage.seven_day_oauth_apps)
        updateUsageItem(key: "seven_day_cowork", limit: usage.seven_day_cowork)

        // Extra usage (special format)
        if let e = usage.extra_usage, e.is_enabled,
           let used = e.used_credits, let limit = e.monthly_limit, let util = e.utilization {
            let extraText = String(format: "Extra: $%.2f/$%.0f", used / 100, limit / 100)
            let extraDetail = String(format: "%.0f%%", util)
            usageItems["extra_usage"]?.title = String(format: "Extra: $%.2f/$%.0f (%.0f%%)", used / 100, limit / 100, util)
            usageItems["extra_usage"]?.attributedTitle = tabbedMenuItemString(extraText, extraDetail)
        } else {
            usageItems["extra_usage"]?.title = "Extra: --"
            usageItems["extra_usage"]?.attributedTitle = nil
        }

        // 5-hour specific: reset date, transitions, menu bar title
        if let h = usage.five_hour {
            let pct = Int(h.utilization)
            let reset = h.resets_at.map { formatReset($0) } ?? "--"

            if let resetStr = h.resets_at {
                let parsedDate = isoFormatter.date(from: resetStr) ?? isoFormatterNoFrac.date(from: resetStr)

                if let newResetDate = parsedDate {
                    if let lastReset = lastKnownResetDate,
                       abs(newResetDate.timeIntervalSince(lastReset)) > 60 {
                        triggerAlarmIfNeeded(endedSessionUtil: lastSessionFinalUtil)
                    }
                    fiveHourResetDate = newResetDate
                    lastKnownResetDate = newResetDate
                    scheduleAlarmCheckTimer(for: newResetDate)
                }
            }

            let newUtil = h.utilization
            if previousFiveHourUtil >= 0 && previousFiveHourUtil < 100 && newUtil >= 100 {
                if alert100Enabled {
                    playClicks(count: 2, soundName: selectedSoundName)
                }
            }
            lastSessionFinalUtil = newUtil
            previousSessionHadUsage = newUtil > 0
            previousFiveHourUtil = newUtil

            let excl = alarmCondition != 0 ? "!" : ""
            if pct >= 100 {
                if let e = usage.extra_usage, e.is_enabled, let spent = e.used_credits, let util = e.utilization {
                    let dollars = spent / 100
                    if util >= 100 {
                        currentPct = String(format: "$%.2f%@", dollars, excl)
                    } else {
                        currentPct = String(format: "$%.2f%@", dollars, excl)
                    }
                } else {
                    currentPct = "\(reset)\(excl)"
                }
            } else {
                currentPct = "\(pct)%"
            }

            if !isHovering && !isAutoShowing {
                statusItem.button?.title = currentPct
            }
            isAutoShowing = false
            scheduleAutoShow()
        }

        // Extra usage transition detection
        if let e = usage.extra_usage, let util = e.utilization {
            if previousExtraUtil >= 0 && previousExtraUtil < 100 && util >= 100 {
                if alertLimitEnabled {
                    playClicks(count: 3, soundName: selectedSoundName)
                }
            }
            previousExtraUtil = util
        }

        // Updated time
        let stale = isDataStale() ? " (stale)" : ""
        updatedItem.title = "Updated: \(timeFormatter.string(from: Date()))\(stale)"
    }

    func isDataStale() -> Bool {
        guard let last = lastFetchDate else { return false }
        return Date().timeIntervalSince(last) > refreshInterval * 2
    }

    // MARK: - Alarm Logic

    func scheduleAlarmCheckTimer(for resetDate: Date) {
        alarmCheckTimer?.invalidate()
        let fireDate = resetDate.addingTimeInterval(1)
        let delay = fireDate.timeIntervalSinceNow
        guard delay > 0 else { return }
        alarmCheckTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.refresh()
        }
    }

    func triggerAlarmIfNeeded(endedSessionUtil: Double) {
        guard alarmCondition != 0 else { return }
        if alarmSkipIfPrevZero && !previousSessionHadUsage { return }

        var shouldAlarm = false
        switch alarmCondition {
        case 1: shouldAlarm = endedSessionUtil >= 100
        case 2: shouldAlarm = endedSessionUtil > 0
        case 3: shouldAlarm = true
        default: break
        }

        guard shouldAlarm else { return }
        guard !alarmIsPlaying else { return }

        alarmIsPlaying = true
        playAlarmBursts(soundName: selectedSoundName, checkMuted: { [weak self] in
            return self?.isHovering ?? false
        }) { [weak self] in
            self?.alarmIsPlaying = false
        }
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
