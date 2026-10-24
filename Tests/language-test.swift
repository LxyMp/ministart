import Foundation

/// Pins how a stored `AppleLanguages` list reads back, and what each choice launches into.
@main
@MainActor
struct LanguageTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    static func main() {
        print("# a stored list reads back as the choice that wrote it")
        check("nothing stored is English", AppLanguage(storedPreferences: nil) == .english)
        check("an empty list is English", AppLanguage(storedPreferences: []) == .english)
        check(
            "a fresh installation selects the system language",
            AppLanguage(storedPreferences: nil, systemPreferences: ["zh-Hans"]) == .chineseSimplified)
        check(
            "an unsupported system language falls back to English",
            AppLanguage(storedPreferences: nil, systemPreferences: ["it-IT"]) == .english)
        check(
            "a stored choice overrides the system language",
            AppLanguage(storedPreferences: ["zh-Hans"], systemPreferences: ["en-US"]) == .chineseSimplified)
        check(
            "an empty stored choice keeps the English fallback",
            AppLanguage(storedPreferences: [], systemPreferences: ["zh-Hans"]) == .english)
        for language in AppLanguage.allCases {
            check(
                "a fresh installation supports \(language.rawValue)",
                AppLanguage(storedPreferences: nil, systemPreferences: [language.rawValue]) == language)
            check(
                "\(language.rawValue) round-trips",
                AppLanguage(storedPreferences: [language.rawValue]) == language)
        }

        print("# System Settings' regional tags land on the shipped language")
        check(
            "zh-Hans-CN is Simplified Chinese",
            AppLanguage(storedPreferences: ["zh-Hans-CN"]) == .chineseSimplified)
        check("an unshipped language reads as English", AppLanguage(storedPreferences: ["it"]) == .english)

        print("# each choice launches into its own localization")
        let shipped = ["en", "zh-Hans"]
        for language in AppLanguage.allCases {
            check(
                "\(language.rawValue) resolves to its bundled localization",
                Bundle.preferredLocalizations(from: shipped, forPreferences: [language.rawValue]).first
                    == language.rawValue)
        }

        print("# every language names itself")
        check(
            "titles are distinct",
            Set(AppLanguage.allCases.map(\.title)).count == AppLanguage.allCases.count)
        check("an unknown raw value is rejected", AppLanguage(rawValue: "klingon") == nil)

        do {
            try checkCatalogs()
        } catch {
            check("catalogs compile and load", false, error.localizedDescription)
        }

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func checkCatalogs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-languages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for catalog in ["Localizable", "InfoPlist"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "xcstringstool", "compile", "Tinycast/Resources/\(catalog).xcstrings",
                "--output-directory", root.path
            ]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                check("\(catalog) compiles", false)
                return
            }
        }

        let clips: [String: (String, String)] = [
            "zh-Hans": ("1 条剪贴内容", "2 条剪贴内容")
        ]
        let contextualLabels: [(key: String, source: String, overrides: [String: String])] = [
            ("emoji-skin-tone-light", "Light", ["zh-Hans": "浅色"]),
            ("emoji-skin-tone-medium", "Medium", ["zh-Hans": "中等"]),
            ("emoji-skin-tone-dark", "Dark", ["zh-Hans": "深色"])
        ]
        // en is the source language: its strings are the keys, so only zh-Hans gets an lproj.
        for code in ["zh-Hans"] {
            guard let bundle = Bundle(url: root.appendingPathComponent("\(code).lproj")),
                let expected = clips[code]
            else {
                check("\(code) resources exist", false)
                continue
            }
            let locale = Locale(identifier: code)
            let one = 1
            let two = 2
            check(
                "\(code) singular is selected at runtime",
                String(localized: "\(one) clips", bundle: bundle, locale: locale) == expected.0)
            check(
                "\(code) plural is selected at runtime",
                String(localized: "\(two) clips", bundle: bundle, locale: locale) == expected.1)
            let size = "5 MB"
            let reordered = String(
                localized: "Reclaims \(size) from \(two) items.", bundle: bundle, locale: locale)
            check(
                "\(code) mixed string and count arguments survive translation",
                reordered.contains(size) && reordered.contains("2") && !reordered.contains("%@"))
            let privacy = bundle.localizedString(
                forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist")
            check("\(code) camera privacy prompt loads", privacy.contains("Tinycast"))

            if code == "en" || code == "fr" {
                for (key, french) in [
                    "Pop to Root Search": "Revenir à la recherche principale",
                    "Pop to root": "Revenir à la recherche principale",
                    "Close window and pop to root": "Fermer la fenêtre et revenir à la recherche principale",
                    "Hidden from root search": "Masqué de la recherche principale",
                    "Hide from Root Search": "Masquer de la recherche principale",
                    "Show in root search": "Afficher dans la recherche principale"
                ] {
                    check(
                        "\(code) root-search terminology is preserved for \(key)",
                        bundle.localizedString(forKey: key, value: nil, table: nil)
                            == (code == "fr" ? french : key))
                }
            }

            for label in contextualLabels {
                let expected =
                    label.overrides[code]
                    ?? bundle.localizedString(forKey: label.source, value: nil, table: nil)
                check(
                    "\(code) contextual label \(label.key)",
                    bundle.localizedString(forKey: label.key, value: nil, table: nil) == expected)
            }
            if code == "fr" {
                for (key, expected) in [
                    "Medium": "Moyenne", "High": "Élevée", "Light": "Clair", "Dark": "Sombre",
                    "Time": "Heure", "Center": "Centrer", "Pinned": "Épinglés",
                    "On": "Activé", "Off": "Désactivé", "Untitled": "Sans titre"
                ] {
                    check(
                        "French label \(key) resolves in its context",
                        bundle.localizedString(forKey: key, value: nil, table: nil) == expected)
                }
                let fill = "50 %"
                for count in [0, 1, 2] {
                    let announcement = String(
                        localized: "Context \(fill), \(count) of \(count) messages sent",
                        bundle: bundle, locale: locale)
                    let suffix = count > 1 ? "messages envoyés" : "message envoyé"
                    check("French context announcement agrees for \(count)", announcement.hasSuffix(suffix))
                }
            }

            if code == "en" || code == "ru" {
                let expectedPair = code == "en" ? "1 window · 2 displays" : "1 окно · 2 дисплея"
                check(
                    "\(code) plural substitutions select each argument independently",
                    String(
                        localized: "\(one) windows · \(two) displays", bundle: bundle, locale: locale)
                        == expectedPair)
                let expectedReverse = code == "en" ? "2 windows · 1 display" : "2 окна · 1 дисплей"
                check(
                    "\(code) the second count can be singular independently",
                    String(
                        localized: "\(two) windows · \(one) displays", bundle: bundle, locale: locale)
                        == expectedReverse)
            }
            if code == "ru" {
                let five = 5
                let twentyOne = 21
                check(
                    "Russian many is selected at runtime",
                    String(localized: "\(five) windows", bundle: bundle, locale: locale) == "5 окон")
                check(
                    "Russian 21 selects one rather than other",
                    String(localized: "\(twentyOne) windows", bundle: bundle, locale: locale) == "21 окно")
            }
        }
    }
}
