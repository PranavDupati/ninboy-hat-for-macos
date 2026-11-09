//
//  NinboyHatPatcher.swift
//  Ninboy Hat for macOS - Native Port Builder & Patcher GUI
//
//  A native macOS utility to select a legally dumped .nup container and
//  apply Apple Silicon native enhancements, crash fixes, KBM UI adaptations,
//  and offline shader pipeline archives with a single click.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Build State & Engine Model

class PatcherModel: ObservableObject {
    // File Paths
    @Published var nupPath: String = ""
    @Published var outputDirectory: String = ""
    @Published var builtAppPath: String = ""
    @Published var isAppBuilt: Bool = false
    
    // Core Game Settings
    @Published var fpsTarget: String = "60" // 30, 60, 0
    @Published var consoleMode: String = "0" // 0: Handheld, 1: Docked
    @Published var resolutionPreset: String = "0" // 0: Normal, 1: Potato
    @Published var gameLanguage: String = "en-US"
    @Published var displayMode: String = "1" // 1: Fullscreen, 0: Window
    
    // Controls & Prompts
    @Published var inGamePrompts: String = "keyboard" // keyboard, controller
    @Published var mouseSensitivity: Double = 300.0 // 20 - 500
    @Published var gameRumble: Bool = true
    
    // Graphics & Upscaling
    @Published var upscaler: String = "fsr4" // fsr4, metalfx, off
    @Published var frameGen: String = "metalfx" // metalfx, fsr4, off
    
    // Advanced Stability & Patches
    @Published var includeFullPipelineArchive: Bool = true
    @Published var ramOptimization: Bool = true
    @Published var lKeyCrashFix: Bool = true
    @Published var zeldasLullabyFix: Bool = true
    @Published var hyruleTextureFix: Bool = true
    @Published var dispatchOverlap: Bool = true
    
    // Execution & Progress State
    @Published var isBuilding: Bool = false
    @Published var buildProgress: Double = 0.0
    @Published var currentPhase: String = "Ready"
    @Published var logLines: [String] = []
    @Published var buildError: String? = nil
    @Published var autoLaunchOnComplete: Bool = true
    
    private var process: Process?
    
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultGamesDir = "\(home)/Documents/Switch 2 Games"
        self.outputDirectory = defaultGamesDir
        
        detectNupFile(in: defaultGamesDir)
        checkBuiltApp(in: defaultGamesDir)
    }
    
    func detectNupFile(in directory: String) {
        let fm = FileManager.default
        let knownPaths = [
            "\(directory)/The Legend of Zelda Ocarina of Time.nup",
            "\(directory)/0400486024DEC000.nup",
            "\(fm.homeDirectoryForCurrentUser.path)/Downloads/The Legend of Zelda Ocarina of Time.nup"
        ]
        
        for path in knownPaths {
            if fm.fileExists(atPath: path) {
                self.nupPath = path
                return
            }
        }
        
        if let files = try? fm.contentsOfDirectory(atPath: directory) {
            for f in files where f.hasSuffix(".nup") {
                self.nupPath = "\(directory)/\(f)"
                return
            }
        }
    }
    
    func checkBuiltApp(in directory: String) {
        let app = "\(directory)/Ocarina of Time.app"
        if FileManager.default.fileExists(atPath: app) {
            self.builtAppPath = app
            self.isAppBuilt = true
        } else {
            self.isAppBuilt = false
        }
    }
    
    func resetToDefaults() {
        fpsTarget = "60"
        consoleMode = "0"
        resolutionPreset = "0"
        gameLanguage = "en-US"
        displayMode = "1"
        inGamePrompts = "keyboard"
        mouseSensitivity = 300.0
        gameRumble = true
        upscaler = "fsr4"
        frameGen = "metalfx"
        includeFullPipelineArchive = true
        ramOptimization = true
        lKeyCrashFix = true
        zeldasLullabyFix = true
        hyruleTextureFix = true
        dispatchOverlap = true
    }
    
    func syncSettings() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let repo = "\(home)/kid-with-sword-remake"
        
        var envTxt = "# Ninboy Hat Engine Environment (RAM & Swap Optimized for 16 GB unified memory)\n"
        if ramOptimization {
            envTxt += "DM_PSO_MANIFEST=off\n"
            envTxt += "DM_GUEST_FILE=1\n"
            envTxt += "DM_GUEST_FILE_CHUNK=1G\n"
            envTxt += "DM_TEX_RELEASE_METHOD=free\n"
            envTxt += "DM_NVN_TEX_SOFT=1\n"
            envTxt += "DM_NVN_TEX_SOFT_ARRAYS=0\n"
            envTxt += "DM_NVN_TEX_SOFT_LEVELS=1\n"
        }
        envTxt += "DM_UPSCALER=metalfx\n"
        envTxt += "DM_PRESENT_UPSCALE=off\n"
        envTxt += "DM_FPS_HOLD=off\n"
        envTxt += "DM_FRAME_WG=1\n"
        envTxt += "DM_NVN_ENC_THREAD=1\n"
        envTxt += "DM_TEX_RELEASE=1\n"
        envTxt += "DM_FULLSCREEN=\(displayMode)\n"
        envTxt += "DM_FOCUS_KEEP=1\n"
        envTxt += "DM_THERMAL_CAP=0\n"
        envTxt += "DM_ALIAS_SIZE=0x200000000\n"
        envTxt += "DM_NVN_DISPATCH_OVERLAP=\(dispatchOverlap ? "1" : "0")\n"
        envTxt += "DM_NVN_PREDICT=1\n"
        envTxt += "DM_PSO_WAITLOG=0\n"
        
        try? envTxt.write(toFile: "\(repo)/mac_env.txt", atomically: true, encoding: .utf8)
        
        let appSupportDir = "\(home)/Library/Application Support/nxnative/0400486024DEC000"
        try? fm.createDirectory(atPath: appSupportDir, withIntermediateDirectories: true)
        try? envTxt.write(toFile: "\(appSupportDir)/env.txt", atomically: true, encoding: .utf8)
        
        if !builtAppPath.isEmpty && fm.fileExists(atPath: builtAppPath) {
            let bundleEnv = "\(builtAppPath)/Contents/Resources/dm/env.txt"
            try? envTxt.write(toFile: bundleEnv, atomically: true, encoding: .utf8)

            let plistPath = "\(builtAppPath)/Contents/Info.plist"
            let keys: [(String, String, String)] = [
                ("LSSupportsGameMode", "-bool", "true"),
                ("GCSupportsGameMode", "-bool", "true"),
                ("GCSupportsControllerUserInteraction", "-bool", "true"),
                ("LSApplicationCategoryType", "-string", "public.app-category.games"),
                ("NSPrincipalClass", "-string", "NSApplication")
            ]
            for (key, type, val) in keys {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
                p.arguments = ["-replace", key, type, val, plistPath]
                try? p.run()
                p.waitUntilExit()
            }

            let pXattr = Process()
            pXattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            pXattr.arguments = ["-cr", builtAppPath]
            try? pXattr.run()
            pXattr.waitUntilExit()

            let pSignExe = Process()
            pSignExe.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            pSignExe.arguments = ["-f", "-s", "-", "\(builtAppPath)/Contents/MacOS/nxnative"]
            try? pSignExe.run()
            pSignExe.waitUntilExit()

            let pSign = Process()
            pSign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            pSign.arguments = ["-f", "-s", "-", builtAppPath]
            try? pSign.run()
            pSign.waitUntilExit()

            let lsreg = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            if fm.fileExists(atPath: lsreg) {
                let pReg = Process()
                pReg.executableURL = URL(fileURLWithPath: lsreg)
                pReg.arguments = ["-f", builtAppPath]
                try? pReg.run()
                pReg.waitUntilExit()
            }

            // Register LSIdentifiedGame bookmark for macOS Game Mode policy
            let bundleID = "org.nxnative.0400486024dec000"
            let lsPlistPath = ("~/Library/Preferences/com.apple.LaunchServices/com.apple.LaunchServices.plist" as NSString).expandingTildeInPath
            if let bookmark = try? URL(fileURLWithPath: builtAppPath).bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
               let plistData = try? Data(contentsOf: URL(fileURLWithPath: lsPlistPath)),
               var dict = (try? PropertyListSerialization.propertyList(from: plistData, options: .mutableContainersAndLeaves, format: nil)) as? [String: Any] {
                var games = dict["LSIdentifiedGame"] as? [String: Any] ?? [:]
                games[bundleID] = [bookmark, 3]
                dict["LSIdentifiedGame"] = games
                if let outData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) {
                    try? outData.write(to: URL(fileURLWithPath: lsPlistPath))
                }
            }

            // Ensure app is recognized by gamepolicyd in ~/Applications if installed elsewhere
            if !builtAppPath.hasPrefix("/Applications/") && !builtAppPath.hasPrefix("\(home)/Applications/") {
                let userApps = "\(home)/Applications"
                try? fm.createDirectory(atPath: userApps, withIntermediateDirectories: true)
                let linkPath = "\(userApps)/Ocarina of Time.app"
                try? fm.removeItem(atPath: linkPath)
                try? fm.createSymbolicLink(atPath: linkPath, withDestinationPath: builtAppPath)
                if fm.fileExists(atPath: lsreg) {
                    let pReg2 = Process()
                    pReg2.executableURL = URL(fileURLWithPath: lsreg)
                    pReg2.arguments = ["-f", linkPath]
                    try? pReg2.run()
                    pReg2.waitUntilExit()
                }
            }
        }
    }
    
    func launchGame() {
        guard !builtAppPath.isEmpty, FileManager.default.fileExists(atPath: builtAppPath) else { return }
        syncSettings()
        let url = URL(fileURLWithPath: builtAppPath)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    
    func showInFinder() {
        guard !builtAppPath.isEmpty else { return }
        let url = URL(fileURLWithPath: builtAppPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    func startBuild() {
        guard !nupPath.isEmpty else {
            buildError = "Please select a valid .nup file."
            return
        }
        guard FileManager.default.fileExists(atPath: nupPath) else {
            buildError = "The selected .nup file does not exist on disk."
            return
        }
        
        isBuilding = true
        buildProgress = 0.05
        currentPhase = "Preparing environment..."
        logLines = ["[Ninboy Hat Patcher] Starting native compilation & patch pipeline..."]
        buildError = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.executeBuildPipeline()
        }
    }
    
    private func appendLog(_ text: String) {
        DispatchQueue.main.async {
            self.logLines.append(text)
            if self.logLines.count > 1000 {
                self.logLines.removeFirst(self.logLines.count - 1000)
            }
        }
    }
    
    private func executeBuildPipeline() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let supportDir = "\(home)/Library/Application Support/NinboyHat"
        try? fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        
        // 1. Locate build_native_port.sh in Bundle resources, support dir, or development repo
        var scriptPath: String? = nil
        let candidateScripts = [
            Bundle.main.resourcePath.map { "\($0)/build_native_port.sh" },
            "\(supportDir)/build_native_port.sh",
            "\(home)/kid-with-sword-remake/build_native_port.sh",
            "\(home)/ninboy-hat-for-macos/build_native_port.sh"
        ].compactMap { $0 }
        
        for candidate in candidateScripts {
            if fm.fileExists(atPath: candidate) {
                scriptPath = candidate
                break
            }
        }
        
        guard let finalScript = scriptPath, fm.fileExists(atPath: finalScript) else {
            DispatchQueue.main.async {
                self.isBuilding = false
                self.buildError = "Build script could not be located inside 'Ninboy Hat Patcher.app/Contents/Resources/' or system paths. If running from DMG, please drag the app to Applications first."
            }
            return
        }
        
        // 2. Identify or provision the translation engine
        var repo = "\(supportDir)/engine"
        let candidateRepos = [
            "\(home)/kid-with-sword-remake",
            "\(supportDir)/engine",
            "\(home)/ninboy-hat-for-macos",
            Bundle.main.resourcePath
        ].compactMap { $0 }
        
        for r in candidateRepos {
            if fm.fileExists(atPath: "\(r)/scripts/build_ipa_from_nsp.py") {
                repo = r
                break
            }
        }
        
        // Update mac_env.txt and nxnative Application Support with chosen options
        syncSettings()
        
        // Execute build_native_port.sh
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        let workDir = "\(outputDirectory)/0400486024DEC000_build-kid"
        let psoArchive = "\(workDir)/pso/mac/applegpu_g15g.mtl4a"
        let canFastPackage = fm.fileExists(atPath: psoArchive)
        
        let action = canFastPackage ? "--app-only" : "--all"
        proc.arguments = [finalScript, action]
        
        var env = ProcessInfo.processInfo.environment
        let standardPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(home)/.cargo/bin",
            "\(home)/.local/bin",
            "\(home)/.pyenv/shims",
            "/Library/Frameworks/Python.framework/Versions/Current/bin",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin"
        ]
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = (standardPaths + [currentPath]).joined(separator: ":")
        
        env["REPO"] = repo
        env["SUPPORT_DIR"] = supportDir
        env["GAMES_DIR"] = outputDirectory
        env["NUP"] = nupPath
        env["WORK"] = workDir
        env["APP"] = "\(outputDirectory)/Ocarina of Time.app"
        if let res = Bundle.main.resourcePath {
            env["BUNDLE_RESOURCES"] = res
        }
        
        // Helper to verify a python binary is >= 3.12
        func isPython312(_ path: String) -> Bool {
            guard fm.isExecutableFile(atPath: path) else { return false }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["-c", "import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)"]
            try? p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        }
        
        let existingVenv = "\(supportDir)/venv/bin/python3"
        if fm.fileExists(atPath: existingVenv) {
            if isPython312(existingVenv) {
                env["PY"] = existingVenv
            } else {
                appendLog("! Found outdated Python environment at \(supportDir)/venv. Removing to rebuild with Python 3.12+...")
                try? fm.removeItem(atPath: "\(supportDir)/venv")
            }
        }
        
        if env["PY"] == nil {
            let nxVenv = "\(home)/nxnative/.venv/bin/python3"
            if isPython312(nxVenv) {
                env["PY"] = nxVenv
            } else {
                let candidates = [
                    "/opt/homebrew/bin/python3.13",
                    "/opt/homebrew/bin/python3.12",
                    "/opt/homebrew/opt/python@3.12/bin/python3.12",
                    "/opt/homebrew/opt/python@3.12/bin/python3",
                    "/opt/homebrew/opt/python@3.13/bin/python3.13",
                    "/opt/homebrew/opt/python@3.13/bin/python3",
                    "/opt/homebrew/bin/python3",
                    "/usr/local/bin/python3.13",
                    "/usr/local/bin/python3.12",
                    "/usr/local/bin/python3",
                    "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
                    "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
                    "\(home)/.pyenv/shims/python3.12",
                    "\(home)/.pyenv/shims/python3",
                    "\(home)/.local/bin/python3.12",
                    "\(home)/.local/bin/python3"
                ]
                for cand in candidates {
                    if isPython312(cand) {
                        env["PY"] = cand
                        break
                    }
                }
            }
        }
        proc.environment = env
        
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.process = proc
        
        DispatchQueue.main.async {
            self.currentPhase = canFastPackage ? "Packaging native app with precompiled 42k pipeline archive..." : "Building shaders & packaging app..."
            self.buildProgress = 0.25
        }
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            let lines = str.components(separatedBy: .newlines)
            for l in lines where !l.isEmpty {
                self?.appendLog(l)
                if l.contains("unpack") {
                    DispatchQueue.main.async { self?.currentPhase = "Unpacking game assets..."; self?.buildProgress = 0.35 }
                } else if l.contains("shader split") {
                    DispatchQueue.main.async { self?.currentPhase = "Analyzing shader stages..."; self?.buildProgress = 0.50 }
                } else if l.contains("Mac shaders") {
                    DispatchQueue.main.async { self?.currentPhase = "Translating shaders to Metal..."; self?.buildProgress = 0.65 }
                } else if l.contains("Pipeline archive") {
                    DispatchQueue.main.async { self?.currentPhase = "Generating Metal 4 pipeline archive..."; self?.buildProgress = 0.85 }
                } else if l.contains("Mac app") || l.contains("Packaging") {
                    DispatchQueue.main.async { self?.currentPhase = "Packaging & signing Ocarina of Time.app..."; self?.buildProgress = 0.95 }
                }
            }
        }
        
        do {
            try proc.run()
            proc.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            
            DispatchQueue.main.async {
                self.isBuilding = false
                if proc.terminationStatus == 0 {
                    self.buildProgress = 1.0
                    self.currentPhase = "Done! Game built successfully."
                    self.checkBuiltApp(in: self.outputDirectory)
                    self.syncSettings()
                    if self.autoLaunchOnComplete {
                        self.launchGame()
                    }
                } else {
                    self.buildError = "Build exited with status \(proc.terminationStatus)."
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.isBuilding = false
                self.buildError = error.localizedDescription
            }
        }
    }
}

// MARK: - Auto-Updater & GitHub Release Manager

class UpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var isChecking: Bool = false
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseNotes: String = ""
    @Published var releaseUrl: URL? = nil
    @Published var downloadUrl: URL? = nil
    
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var updateStatus: String = ""
    @Published var updateError: String? = nil
    
    @Published var showUpdateSheet: Bool = false
    @Published var upToDateMessage: String? = nil
    
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1.1"
    }
    
    private var downloadTask: URLSessionDownloadTask?
    
    func checkForUpdates(userInitiated: Bool = false) {
        guard !isChecking, !isDownloading else { return }
        isChecking = true
        updateError = nil
        
        guard let url = URL(string: "https://api.github.com/repos/PranavDupati/ninboy-hat-for-macos/releases/latest") else {
            isChecking = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("NinboyHatPatcher/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                
                if let error = error {
                    if userInitiated {
                        self.updateError = "Unable to check for updates: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    if userInitiated {
                        self.updateError = "Could not parse latest release from GitHub."
                    }
                    return
                }
                
                let cleanTag = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                self.latestVersion = cleanTag
                self.releaseNotes = json["body"] as? String ?? "No release notes provided."
                if let htmlStr = json["html_url"] as? String, let u = URL(string: htmlStr) {
                    self.releaseUrl = u
                }
                
                // Find ZIP asset
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           let dlStr = asset["browser_download_url"] as? String,
                           let dlUrl = URL(string: dlStr),
                           name.hasSuffix(".zip") {
                            self.downloadUrl = dlUrl
                            break
                        }
                    }
                }
                
                if self.isVersion(cleanTag, greaterThan: self.currentVersion) {
                    self.updateAvailable = true
                    self.showUpdateSheet = true
                } else {
                    self.updateAvailable = false
                    if userInitiated {
                        self.upToDateMessage = "Ninboy Hat Patcher is up to date (v\(self.currentVersion))."
                    }
                }
            }
        }.resume()
    }
    
    func downloadAndInstallUpdate() {
        guard let url = downloadUrl, !isDownloading else {
            if let relUrl = releaseUrl {
                NSWorkspace.shared.open(relUrl)
            }
            return
        }
        
        isDownloading = true
        downloadProgress = 0.0
        updateStatus = "Downloading v\(latestVersion)..."
        updateError = nil
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let mbWritten = Double(totalBytesWritten) / 1_048_576.0
            let mbTotal = Double(totalBytesExpectedToWrite) / 1_048_576.0
            DispatchQueue.main.async {
                self.downloadProgress = progress
                self.updateStatus = String(format: "Downloading: %.1f MB / %.1f MB (%.0f%%)", mbWritten, mbTotal, progress * 100)
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        DispatchQueue.main.async {
            self.updateStatus = "Extracting & preparing update..."
        }
        
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ninboy_patcher_update_\(UUID().uuidString)")
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let zipDest = tempDir.appendingPathComponent("update.zip")
        try? fm.moveItem(at: location, to: zipDest)
        
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipDest.path, tempDir.path]
        try? unzip.run()
        unzip.waitUntilExit()
        
        let extractedItems = (try? fm.contentsOfDirectory(atPath: tempDir.path)) ?? []
        var newAppPath: String? = nil
        for item in extractedItems {
            if item.hasSuffix(".app") {
                newAppPath = tempDir.appendingPathComponent(item).path
                break
            }
        }
        
        guard let newApp = newAppPath, fm.fileExists(atPath: newApp) else {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.updateError = "Failed to extract update package."
            }
            return
        }
        
        let currentApp = Bundle.main.bundlePath
        let scriptPath = tempDir.appendingPathComponent("install.sh").path
        let script = """
        #!/bin/bash
        sleep 1
        rm -rf "\(currentApp)"
        cp -R "\(newApp)" "\(currentApp)"
        xattr -dr com.apple.quarantine "\(currentApp)" 2>/dev/null || true
        open "\(currentApp)"
        rm -rf "\(tempDir.path)"
        """
        
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptPath]
        try? chmod.run()
        chmod.waitUntilExit()
        
        DispatchQueue.main.async {
            self.updateStatus = "Relaunching updated version..."
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [scriptPath]
            try? launcher.run()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.updateError = "Download failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let parts1 = v1.components(separatedBy: ".").compactMap { Int($0) }
        let parts2 = v2.components(separatedBy: ".").compactMap { Int($0) }
        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }
}

// MARK: - Native SwiftUI Interface (Matching Game Launcher Window)

struct PatcherMainView: View {
    @ObservedObject var model: PatcherModel
    @StateObject private var updater = UpdateManager()
    @State private var showAdvanced: Bool = false
    @State private var showLog: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Area (Icon + Title + Subtitle)
            HStack(spacing: 14) {
                Image(nsImage: loadGameIcon())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("The Legend of Zelda: Ocarina of Time")
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 8) {
                        Text("Ninboy Hat macOS Port Builder • v\(updater.currentVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if updater.updateAvailable {
                            Button {
                                updater.showUpdateSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("v\(updater.latestVersion) Available")
                                }
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.blue))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
                
                Button {
                    updater.checkForUpdates(userInitiated: true)
                } label: {
                    if updater.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.borderless)
                .help("Check for Updates")
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)
            
            // Grouped Form Area
            Form {
                // Section: Source .nup container
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.nupPath.isEmpty ? "No .nup file selected" : (model.nupPath as NSString).lastPathComponent)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !model.nupPath.isEmpty {
                                Text(fileSizeString(for: model.nupPath))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(model.nupPath.isEmpty ? "Choose File..." : "Change...") {
                            chooseNupFile()
                        }
                    }
                } header: {
                    Text("Source Container (.nup)")
                } footer: {
                    Text("Select your legally dumped .nup file (0400486024DEC000, v131072). Modifications are applied natively on Apple Silicon.")
                }
                
                // Section: Game Configuration
                Section {
                    Picker("Frame rate", selection: $model.fpsTarget) {
                        Text("30 fps (Lock)").tag("30")
                        Text("60 fps (Lock)").tag("60")
                        Text("Unlocked / Unlimited").tag("0")
                    }
                    
                    Picker("Console mode", selection: $model.consoleMode) {
                        Text("Handheld").tag("0")
                        Text("Docked").tag("1")
                    }
                    
                    Picker("Resolution", selection: $model.resolutionPreset) {
                        Text("Normal (1280×720 handheld / 1951×1098 docked)").tag("0")
                        Text("Potato (960×540 shown at 720p)").tag("1")
                    }
                    
                    Picker("Game language", selection: $model.gameLanguage) {
                        Text("American English").tag("en-US")
                        Text("Japanese").tag("ja")
                        Text("European English").tag("en-GB")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Italian").tag("it")
                        Text("Spanish").tag("es")
                    }
                    
                    Picker("Display mode", selection: $model.displayMode) {
                        Text("Fullscreen").tag("1")
                        Text("Window").tag("0")
                    }
                } header: {
                    Text("Game")
                }
                
                // Section: Controls
                Section {
                    Toggle("Game rumble", isOn: $model.gameRumble)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Mouse sensitivity")
                            Spacer()
                            Text("\(Int(model.mouseSensitivity)) %")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.mouseSensitivity, in: 20...500, step: 10)
                    }
                    
                    Picker("In-game button prompts", selection: $model.inGamePrompts) {
                        Text("Keyboard (⏎ Enter / ⌫ Delete / Click)").tag("keyboard")
                        Text("Controller (Diamond A/B/X/Y)").tag("controller")
                    }
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Replaces in-game button icons with unhighlighted Apple SF Symbols styled for PC keyboard & mouse.")
                }
                
                // Section: Graphics & Upscaling
                Section {
                    Picker("Upscaling", selection: $model.upscaler) {
                        Text("FSR 4 (Machine Learning)").tag("fsr4")
                        Text("MetalFX Spatial").tag("metalfx")
                        Text("Standard / Off").tag("off")
                    }
                    
                    Picker("Frame generation", selection: $model.frameGen) {
                        Text("MetalFX Frame Interpolation").tag("metalfx")
                        Text("FSR 4 Frame Generation").tag("fsr4")
                        Text("Off").tag("off")
                    }
                } header: {
                    Text("Graphics & Upscaling")
                } footer: {
                    Text("Generates intermediate frames and leverages Apple Silicon Neural Engine / Metal 4.")
                }
                
                // Section: Advanced Settings (Disclosure Group)
                Section {
                    DisclosureGroup("Advanced settings & crash fixes", isExpanded: $showAdvanced) {
                        Toggle("Metal 4 Offline Pipeline Archive (3.2 GB, 0% stutter)", isOn: $model.includeFullPipelineArchive)
                        Toggle("RAM & Swap Optimization (16 GB Unified Memory)", isOn: $model.ramOptimization)
                        Toggle("L-Key Vibration Crash Fix (nn::hid stubs)", isOn: $model.lKeyCrashFix)
                        Toggle("Zelda's Lullaby Crash Fix (NvPkg selector forwarding)", isOn: $model.zeldasLullabyFix)
                        Toggle("Hyrule Castle & Village Missing Textures Fix", isOn: $model.hyruleTextureFix)
                        Toggle("Overlapped Compute Dispatch (shaves 2-3 ms per frame)", isOn: $model.dispatchOverlap)
                        
                        HStack {
                            Text("Output directory")
                            Spacer()
                            Text((model.outputDirectory as NSString).lastPathComponent)
                                .foregroundStyle(.secondary)
                            Button("Choose...") { chooseOutputDir() }
                        }
                        
                        Button("Reset to tested defaults") {
                            model.resetToDefaults()
                        }
                    }
                }
                
                // Section: Progress & Status
                if model.isBuilding || model.isAppBuilt || model.buildError != nil {
                    Section {
                        if model.isBuilding {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(model.currentPhase)
                                        .font(.subheadline)
                                    Spacer()
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                ProgressView(value: model.buildProgress, total: 1.0)
                            }
                        } else if model.isAppBuilt && model.buildError == nil {
                            HStack {
                                Label("Ocarina of Time.app is ready (33.7 GB, 30,515 precompiled pipelines)", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Button("Show in Finder") {
                                    model.showInFinder()
                                }
                            }
                        }
                        
                        if let err = model.buildError {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text("Build Notice")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.red)
                                }
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                            .padding(.vertical, 4)
                        }
                        
                        DisclosureGroup("Show build output log", isExpanded: $showLog) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(model.logLines.suffix(100), id: \.self) { line in
                                        Text(line)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(4)
                            }
                            .frame(height: 120)
                            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    } header: {
                        Text("Port Status")
                    }
                }
            }
            .formStyle(.grouped)
            
            // Bottom Action Bar
            HStack(spacing: 12) {
                Toggle("Launch game after build", isOn: $model.autoLaunchOnComplete)
                    .toggleStyle(.checkbox)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                
                if model.isAppBuilt && !model.isBuilding {
                    Button("Rebuild / Update") {
                        model.startBuild()
                    }
                    
                    Button("Play") {
                        model.launchGame()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(model.isBuilding ? "Building..." : "Apply Patches & Build App") {
                        model.startBuild()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBuilding || model.nupPath.isEmpty)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 680, idealHeight: 740)
        .sheet(isPresented: $updater.showUpdateSheet) {
            UpdateSheetView(updater: updater)
        }
        .alert(updater.upToDateMessage ?? "", isPresented: Binding(
            get: { updater.upToDateMessage != nil },
            set: { if !$0 { updater.upToDateMessage = nil } }
        )) {
            Button("OK", role: .cancel) { updater.upToDateMessage = nil }
        }
        .onAppear {
            updater.checkForUpdates(userInitiated: false)
        }
    }
    
    private func chooseNupFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "nup") ?? .data, UTType(filenameExtension: "nsp") ?? .data]
        panel.message = "Choose your legally dumped Switch 2 .nup file"
        if panel.runModal() == .OK, let url = panel.url {
            model.nupPath = url.path
        }
    }
    
    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Select Destination Folder for Ocarina of Time.app"
        if panel.runModal() == .OK, let url = panel.url {
            model.outputDirectory = url.path
            model.checkBuiltApp(in: url.path)
        }
    }
    
    private func fileSizeString(for path: String) -> String {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attr[.size] as? Int64 else { return "" }
        let gb = Double(size) / 1_073_741_824.0
        return String(format: "%.1f GB", gb)
    }
    
    private func loadGameIcon() -> NSImage {
        let appIconPath = "/Users/pranavkdupati/Documents/Switch 2 Games/Ocarina of Time.app/Contents/Resources/AppIcon.icns"
        if let img = NSImage(contentsOfFile: appIconPath) {
            return img
        }
        let extractIcon = "/Users/pranavkdupati/Documents/Switch 2 Games/0400486024DEC000_build-kid/extract/v131072/icon.jpg"
        if let img = NSImage(contentsOfFile: extractIcon) {
            return img
        }
        return NSApp.applicationIconImage
    }
}

// MARK: - Auto-Updater Sheet View

struct UpdateSheetView: View {
    @ObservedObject var updater: UpdateManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Available")
                        .font(.headline)
                    Text("Version \(updater.latestVersion) is now available (you have v\(updater.currentVersion)).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Release Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(updater.releaseNotes)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 150)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            if updater.isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: updater.downloadProgress, total: 1.0)
                    Text(updater.updateStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let err = updater.updateError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            HStack(spacing: 10) {
                if let relUrl = updater.releaseUrl {
                    Button("View on GitHub") {
                        NSWorkspace.shared.open(relUrl)
                    }
                }
                
                Spacer()
                
                Button("Later") {
                    dismiss()
                }
                .disabled(updater.isDownloading)
                
                Button(updater.isDownloading ? "Updating..." : "Download & Install") {
                    updater.downloadAndInstallUpdate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(updater.isDownloading)
            }
        }
        .padding(20)
        .frame(width: 480, height: 350)
    }
}

// MARK: - Application Delegate & Main Entry

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    let model = PatcherModel()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = PatcherMainView(model: model)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "The Legend of Zelda: Ocarina of Time"
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct NinboyHatPatcherApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
