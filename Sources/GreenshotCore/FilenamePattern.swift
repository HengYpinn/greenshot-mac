// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Fills Greenshot filename patterns such as `${capturetime:d"yyyy-MM-dd HH_mm_ss"}-${title}`.
///
/// Port of `FillPattern` / `MatchVarEvaluatorInternal` in upstream `Greenshot.Base/Core/FilenameHelper.cs`.
/// A variable is `${name}` or `${name:parameters}`; parameters are separated by `;` (outside quotes):
/// - `p<width>[,<char>]` pads (positive width pads right, negative pads left),
/// - `r<old>,<new>` replaces text in the value,
/// - `d<format>` sets the .NET date format for `capturetime` and `now`,
/// - `s<start>[,<length>]` takes a substring (negative numbers count from the end).
public enum FilenamePattern {
    public static let defaultPattern = "${capturetime:d\"yyyy-MM-dd HH_mm_ss\"}-${title}"
    /// Used when the configured pattern is empty, like upstream's `GetFilename`.
    public static let fallbackPattern = "greenshot ${capturetime}"

    static let maxTitleLength = 80
    static let unsafeReplacement = "_"
    /// The characters .NET's `Path.GetInvalidFileNameChars()` returns on Windows. They are replaced on the Mac too,
    /// so file names stay valid when the screenshots are shared with Windows users.
    static let invalidFilenameCharacters: Set<Character> = {
        var set: Set<Character> = ["\"", "<", ">", "|", ":", "*", "?", "\\", "/"]
        for code in 0..<32 { set.insert(Character(UnicodeScalar(UInt8(code)))) }
        return set
    }()
    /// `Path.GetInvalidPathChars()` on .NET Framework.
    static let invalidPathCharacters: Set<Character> = {
        var set: Set<Character> = ["\"", "<", ">", "|"]
        for code in 0..<32 { set.insert(Character(UnicodeScalar(UInt8(code)))) }
        return set
    }()

    /// Everything a pattern can refer to. Tests pass fixed values; the app uses `Context.current`.
    public struct Context {
        public var captureTime: Date
        public var title: String?
        public var environment: [String: String]
        public var userName: String
        public var hostName: String
        public var homeDirectory: URL
        public var locale: Locale
        public var timeZone: TimeZone
        /// Called once per `${NUM}`: increments and returns the persisted counter (upstream `OutputFileIncrementingNumber`).
        public var nextNumber: () -> UInt
        public var randomIndex: (Int) -> Int

        public init(captureTime: Date,
                    title: String?,
                    environment: [String: String] = [:],
                    userName: String = NSUserName(),
                    hostName: String = Context.shortHostName(),
                    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                    locale: Locale = .current,
                    timeZone: TimeZone = .current,
                    nextNumber: @escaping () -> UInt = { 1 },
                    randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }) {
            self.captureTime = captureTime
            self.title = title
            self.environment = environment
            self.userName = userName
            self.hostName = hostName
            self.homeDirectory = homeDirectory
            self.locale = locale
            self.timeZone = timeZone
            self.nextNumber = nextNumber
            self.randomIndex = randomIndex
        }

        public static func shortHostName() -> String {
            let name = ProcessInfo.processInfo.hostName
            return name.split(separator: ".").first.map(String.init) ?? name
        }
    }

    private static let variableRegex = try! NSRegularExpression(pattern: #"\$\{([^:}]+):?([^}]*)\}"#)

    /// Fills `pattern`. With `filenameSafe` the values are cleaned of characters a file name can't contain,
    /// the literal text of the pattern is kept (so `${YYYY}/${title}` makes a sub folder).
    public static func fill(_ pattern: String, context: Context, filenameSafe: Bool = true) -> String {
        let pattern = pattern.trimmingCharacters(in: .whitespaces).isEmpty ? fallbackPattern : pattern
        let ns = pattern as NSString
        var result = ""
        var last = 0
        for match in variableRegex.matches(in: pattern, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let variable = ns.substring(with: match.range(at: 1))
            let parameters = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
            result += evaluate(variable: variable, parameters: parameters, context: context, filenameSafe: filenameSafe)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    /// Fills a pattern for a file name. A result without a name (empty, or ending in a folder like `${YYYY}/`)
    /// gets the fallback pattern as its name, so the file never lands next to the output folder or is called ".png".
    public static func fileName(_ pattern: String, context: Context) -> String {
        let name = fill(pattern, context: context)
        let lastComponent = name.components(separatedBy: "/").last ?? ""
        guard lastComponent.trimmingCharacters(in: .whitespaces).isEmpty else { return name }
        let folder = name.trimmingCharacters(in: .whitespaces).isEmpty ? "" : name
        return folder + fill(fallbackPattern, context: context)
    }

    public static func makeFilenameSafe(_ value: String) -> String {
        String(value.map { invalidFilenameCharacters.contains($0) ? Character(unsafeReplacement) : $0 })
    }

    public static func makePathSafe(_ value: String) -> String {
        String(value.map { invalidPathCharacters.contains($0) ? Character(unsafeReplacement) : $0 })
    }

    // MARK: - Variables

    private static func evaluate(variable: String, parameters: String, context: Context, filenameSafe: Bool) -> String {
        var padWidth = 0
        var padChar: Character = " "
        var startIndex = 0
        var endIndex = 0
        var dateFormat = "yyyy-MM-dd HH-mm-ss"
        var replacements: [(String, String)] = []

        for parameter in splitParameters(parameters) where !parameter.isEmpty {
            let body = String(parameter.dropFirst())
            switch parameter.first {
            case "p":
                let parts = body.components(separatedBy: ",")
                if let width = Int(parts[0]) { padWidth = width }
                if parts.count > 1, let char = parts[1].first { padChar = char }
            case "r":
                let parts = body.components(separatedBy: ",")
                if parts.count == 2 { replacements.append((parts[0], parts[1])) }
            case "d":
                var format = body
                if format.hasPrefix("\"") { format.removeFirst() }
                if format.hasSuffix("\"") { format.removeLast() }
                dateFormat = format
            case "s":
                let parts = body.components(separatedBy: ",")
                if let start = Int(parts[0]) { startIndex = start }
                if parts.count > 1, let end = Int(parts[1]) { endIndex = end }
            default:
                break
            }
        }

        var value = ""
        if let env = context.environment[variable] {
            value = filenameSafe ? makePathSafe(env) : env
        } else if variable.allSatisfy({ $0 == "R" }) {
            let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
            value = String((0..<variable.count).map { _ in chars[context.randomIndex(chars.count)] })
        } else {
            var title = context.title ?? "Greenshot"
            if title.count > maxTitleLength { title = String(title.prefix(maxTitleLength)) }
            let calendar: Calendar = {
                var c = Calendar(identifier: .gregorian)
                c.timeZone = context.timeZone
                return c
            }()
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: context.captureTime)
            func zeroPadded(_ number: Int?, _ width: Int) -> String {
                if padWidth == 0 { padWidth = -width; padChar = "0" }
                return String(number ?? 0)
            }
            let home = context.homeDirectory
            switch variable {
            case "domain": value = context.hostName
            case "user": value = context.userName
            case "hostname": value = context.hostName
            case "YYYY": value = zeroPadded(parts.year, 4)
            case "MM": value = zeroPadded(parts.month, 2)
            case "DD": value = zeroPadded(parts.day, 2)
            case "hh": value = zeroPadded(parts.hour, 2)
            case "mm": value = zeroPadded(parts.minute, 2)
            case "ss": value = zeroPadded(parts.second, 2)
            case "now", "capturetime":
                let date = variable == "now" ? Date() : context.captureTime
                value = DotNetDateFormat.string(from: date, format: dateFormat, locale: context.locale, timeZone: context.timeZone)
                if filenameSafe { value = makeFilenameSafe(value) }
            case "NUM":
                value = String(context.nextNumber())
                if padWidth == 0 { padWidth = -6; padChar = "0" }
            case "title":
                value = filenameSafe ? makeFilenameSafe(title) : title
            case "MyPictures": value = home.appendingPathComponent("Pictures").path
            case "MyMusic": value = home.appendingPathComponent("Music").path
            case "MyDocuments", "Personal": value = home.appendingPathComponent("Documents").path
            case "Desktop": value = home.appendingPathComponent("Desktop").path
            case "ApplicationData", "LocalApplicationData": value = home.appendingPathComponent("Library/Application Support").path
            default: value = ""
            }
        }

        if padWidth > 0, value.count < padWidth {
            value += String(repeating: padChar, count: padWidth - value.count)
        } else if padWidth < 0, value.count < -padWidth {
            value = String(repeating: padChar, count: -padWidth - value.count) + value
        }

        if startIndex != 0 || endIndex != 0 {
            let length = value.count
            if startIndex < 0 { startIndex = length + startIndex }
            if endIndex < 0 { endIndex = length + endIndex }
            // .NET Substring(start, length) throws when out of range; upstream then keeps the value as it is.
            if endIndex != 0 {
                if startIndex >= 0, endIndex >= 0, startIndex + endIndex <= length {
                    value = String(value.dropFirst(startIndex).prefix(endIndex))
                }
            } else if startIndex >= 0, startIndex <= length {
                value = String(value.dropFirst(startIndex))
            }
        }

        for (old, new) in replacements where !old.isEmpty {
            value = value.replacingOccurrences(of: old, with: new)
        }
        return value
    }

    /// Splits on `;` outside double quotes, like upstream's `SplitRegexp`.
    static func splitParameters(_ parameters: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in parameters {
            if char == "\"" { inQuotes.toggle() }
            if char == ";" && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }
}

/// Formats dates with .NET date format strings (standard ones like `D` and custom ones like `yyyy-MM-dd HH_mm_ss`),
/// so patterns written for Greenshot on Windows give the same file names on the Mac.
public enum DotNetDateFormat {
    public static func string(from date: Date, format: String, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        if format.count == 1, let standard = standardFormat(format, formatter: formatter, date: date) {
            return standard
        }
        formatter.dateFormat = icuPattern(fromDotNet: format)
        return formatter.string(from: date)
    }

    private static func standardFormat(_ format: String, formatter: DateFormatter, date: Date) -> String? {
        func styled(_ dateStyle: DateFormatter.Style, _ timeStyle: DateFormatter.Style) -> String {
            formatter.dateStyle = dateStyle
            formatter.timeStyle = timeStyle
            return formatter.string(from: date)
        }
        func fixed(_ pattern: String, utc: Bool = false) -> String {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if utc { formatter.timeZone = TimeZone(identifier: "UTC") }
            formatter.dateFormat = pattern
            return formatter.string(from: date)
        }
        switch format {
        case "d": return styled(.short, .none)
        case "D": return styled(.full, .none)
        case "t": return styled(.none, .short)
        case "T": return styled(.none, .medium)
        case "f": return styled(.full, .short)
        case "F": return styled(.full, .medium)
        case "g": return styled(.short, .short)
        case "G": return styled(.short, .medium)
        case "M", "m":
            formatter.setLocalizedDateFormatFromTemplate("MMMMd")
            return formatter.string(from: date)
        case "Y", "y":
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            return formatter.string(from: date)
        case "s": return fixed("yyyy-MM-dd'T'HH:mm:ss")
        case "u": return fixed("yyyy-MM-dd HH:mm:ss'Z'", utc: true)
        case "o", "O": return fixed("yyyy-MM-dd'T'HH:mm:ss.SSSSSSSxxx")
        case "R", "r": return fixed("EEE, dd MMM yyyy HH:mm:ss 'GMT'", utc: true)
        default: return nil
        }
    }

    /// Translates a .NET custom date format into an ICU (`DateFormatter.dateFormat`) pattern.
    /// .NET treats letters it doesn't know as literal text, ICU doesn't, so those are quoted.
    public static func icuPattern(fromDotNet format: String) -> String {
        let chars = Array(format)
        var out = ""
        var literal = ""
        func flushLiteral() {
            guard !literal.isEmpty else { return }
            out += "'" + literal.replacingOccurrences(of: "'", with: "''") + "'"
            literal = ""
        }
        func emit(_ token: String) {
            flushLiteral()
            out += token
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "'" || c == "\"" {
                var j = i + 1
                while j < chars.count && chars[j] != c {
                    literal.append(chars[j])
                    j += 1
                }
                i = j + 1
                continue
            }
            if c == "\\" {
                if i + 1 < chars.count { literal.append(chars[i + 1]) }
                i += 2
                continue
            }
            if c == "%" {
                i += 1
                continue
            }
            var run = 1
            while i + run < chars.count && chars[i + run] == c { run += 1 }
            switch c {
            case "y": emit(run <= 2 ? "yy" : String(repeating: "y", count: run))
            case "M": emit(String(repeating: "M", count: min(run, 4)))
            case "d":
                switch run {
                case 1: emit("d")
                case 2: emit("dd")
                case 3: emit("EEE")
                default: emit("EEEE")
                }
            case "H", "h", "m", "s": emit(String(repeating: c, count: min(run, 2)))
            case "f", "F": emit(String(repeating: "S", count: min(run, 7)))
            case "t": emit("a")
            case "z": emit(run >= 3 ? "xxx" : "x")
            case "K": emit("xxx")
            case "g": emit("G")
            default:
                // Unknown letters, digits and separators ('-', '_', ':', '/', ...) are literal text in .NET.
                literal += String(repeating: c, count: run)
            }
            i += run
        }
        flushLiteral()
        return out
    }
}

extension FilenamePattern {
    /// The variables and options of a pattern, for Settings › Output.
    public static let helpText = """
        ${capturetime:d"yyyy-MM-dd HH_mm_ss"}  capture time, .NET date format
        ${title}  window title    ${user}  user name    ${hostname}  computer name
        ${YYYY} ${MM} ${DD} ${hh} ${mm} ${ss}  date and time parts
        ${NUM}  counter (000001)    ${RRRR}  random characters
        ${Desktop} ${MyPictures} ${MyDocuments}  folders    ${HOME} or any environment variable
        Options after a colon, separated by ';': p<width>[,char] pad, s<start>[,length] substring, r<old>,<new> replace
        A '/' in the pattern makes sub folders, e.g. ${YYYY}/${MM}/${title}
        """
}
