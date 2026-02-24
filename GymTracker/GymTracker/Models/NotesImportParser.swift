import Foundation
import CryptoKit

final class NotesImportParser {
    func parseBatch(from text: String, defaultWeightUnit: WeightUnit) -> NotesImportBatch {
        let normalizedText = normalizeLineEndings(text)
        let lines = normalizedText.components(separatedBy: .newlines)
        let dateLineIndices = lines.indices.filter { isDateHeaderLine(lines[$0]) }

        let blocks: [String]
        if dateLineIndices.isEmpty {
            blocks = [normalizedText]
        } else {
            var splitBlocks: [String] = []
            for (offset, start) in dateLineIndices.enumerated() {
                let nextStart = offset + 1 < dateLineIndices.count ? dateLineIndices[offset + 1] : lines.count
                let blockStart = (offset == 0) ? 0 : start
                let block = lines[blockStart..<nextStart].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !block.isEmpty {
                    splitBlocks.append(block)
                }
            }
            blocks = splitBlocks.isEmpty ? [normalizedText] : splitBlocks
        }

        let drafts = blocks.map { block in
            var draft = parseSingleSession(from: block, defaultWeightUnit: defaultWeightUnit)
            draft.importHash = generateImportHash(for: block)
            return draft
        }

        return NotesImportBatch(drafts: drafts)
    }

    func parseSingleSession(from text: String, defaultWeightUnit: WeightUnit) -> NotesImportDraft {
        let normalizedText = normalizeLineEndings(text)
        let rawLines = normalizedText.components(separatedBy: .newlines)
        var warnings: [String] = []
        var unknownLines: [String] = []
        var items: [ParsedItem] = []

        let trimmedNonEmptyLines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var parsedDate: Date?
        var routineNameRaw: String?
        var startTime: Date?
        var endTime: Date?

        var consumedLineIndices: Set<Int> = []

        if let headerIndex = rawLines.firstIndex(where: { isDateHeaderLine($0) }) {
            consumedLineIndices.insert(headerIndex)
            let headerLine = rawLines[headerIndex].trimmingCharacters(in: .whitespacesAndNewlines)

            let parsedHeader = parseDateHeader(headerLine)
            parsedDate = parsedHeader.date
            routineNameRaw = parsedHeader.routineNameRaw

            if let date = parsedDate {
                if let timeRange = parseTimeRange(in: headerLine) {
                    consumedLineIndices.insert(headerIndex)
                    let mappedTimes = mapTimeRangeToDate(timeRange, on: date)
                    startTime = mappedTimes.start
                    endTime = mappedTimes.end
                } else {
                    let searchUpperBound = min(rawLines.count, headerIndex + 4)
                    for index in (headerIndex + 1)..<searchUpperBound {
                        let line = rawLines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !line.isEmpty else { continue }
                        if let timeRange = parseTimeRange(in: line) {
                            consumedLineIndices.insert(index)
                            let mappedTimes = mapTimeRangeToDate(timeRange, on: date)
                            startTime = mappedTimes.start
                            endTime = mappedTimes.end
                            break
                        }
                        if likelyTimeRangeText(line) {
                            warnings.append("Time range could not be parsed: \(line)")
                            consumedLineIndices.insert(index)
                            break
                        }
                    }
                }
            }
        }

        for index in rawLines.indices {
            if consumedLineIndices.contains(index) {
                continue
            }

            let originalLine = rawLines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if originalLine.isEmpty {
                continue
            }

            let line = removeNumberPrefix(from: originalLine)
            guard let commaIndex = line.firstIndex(of: ",") else {
                unknownLines.append(originalLine)
                continue
            }

            let name = String(line[..<commaIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(line[line.index(after: commaIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if name.isEmpty || tail.isEmpty {
                unknownLines.append(originalLine)
                continue
            }

            if let cardio = parseCardio(name: name, tail: tail) {
                items.append(.cardio(cardio))
                continue
            }

            if let strengthResult = parseStrength(name: name, tail: tail, defaultWeightUnit: defaultWeightUnit) {
                items.append(.strength(strengthResult.strength))
                warnings.append(contentsOf: strengthResult.warnings)
                continue
            }

            unknownLines.append(originalLine)
        }

        if parsedDate == nil,
           let firstHeaderLikeLine = trimmedNonEmptyLines.first(where: { $0.range(of: #"\d{4}"#, options: .regularExpression) != nil && $0.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil }) {
            warnings.append("Date could not be parsed from header: \(firstHeaderLikeLine)")
        }

        return NotesImportDraft(
            originalText: normalizedText,
            parsedDate: parsedDate,
            startTime: startTime,
            endTime: endTime,
            routineNameRaw: routineNameRaw,
            items: items,
            unknownLines: unknownLines,
            warnings: warnings,
            importHash: generateImportHash(for: normalizedText)
        )
    }
}

private extension NotesImportParser {
    var monthNamePattern: String {
        "(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
    }

    var dateExtractorRegex: NSRegularExpression {
        let pattern = "\\b(\(monthNamePattern))\\s+(\\d{1,2}),\\s*(\\d{4})\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    var timeRangeRegex: NSRegularExpression {
        let pattern = "\\b([01]\\d|2[0-3]):([0-5]\\d)\\s*-\\s*([01]\\d|2[0-3]):([0-5]\\d)\\b"
        return try! NSRegularExpression(pattern: pattern)
    }

    var nxrRegex: NSRegularExpression {
        let pattern = "\\b(\\d+)\\s*x\\s*(\\d+(?:\\.\\d+)?)\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    var setsOfRegex: NSRegularExpression {
        let pattern = "\\b(\\d+)\\s*sets?\\s*of\\s*(\\d+)\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    var weightRegex: NSRegularExpression {
        let pattern = "\\b(\\d+(?:\\.\\d+)?)\\s*(kg|kgs|kilogram|kilograms|lb|lbs|pound|pounds)\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    var restRegex: NSRegularExpression {
        let pattern = "\\b(\\d{1,2}):(\\d{2})\\s*m?\\s*rest\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    var distanceRegex: NSRegularExpression {
        let pattern = "\\b(\\d+(?:\\.\\d+)?)\\s*(km|mi)\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    var durationClockRegex: NSRegularExpression {
        let pattern = "\\b(\\d{1,2}):(\\d{2})\\s*min\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    var durationMinutesRegex: NSRegularExpression {
        let pattern = "\\b(\\d+)\\s*(min|mins|minute|minutes)\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    var paceRegex: NSRegularExpression {
        let pattern = "\\b(\\d{1,2}):(\\d{2})\\s*(av|avg|pace)\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    func normalizeLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    func isDateHeaderLine(_ line: String) -> Bool {
        let range = NSRange(location: 0, length: line.utf16.count)
        return dateExtractorRegex.firstMatch(in: line, options: [], range: range) != nil
    }

    func parseDateHeader(_ headerLine: String) -> (date: Date?, routineNameRaw: String?) {
        let nsRange = NSRange(location: 0, length: headerLine.utf16.count)
        guard let match = dateExtractorRegex.firstMatch(in: headerLine, options: [], range: nsRange),
              let monthRange = Range(match.range(at: 1), in: headerLine),
              let dayRange = Range(match.range(at: 2), in: headerLine),
              let yearRange = Range(match.range(at: 3), in: headerLine),
              let day = Int(headerLine[dayRange]),
              let year = Int(headerLine[yearRange]) else {
            return (nil, nil)
        }

        let monthToken = String(headerLine[monthRange]).lowercased()
        let month = monthNumber(from: monthToken)

        var date: Date?
        if let month {
            var components = DateComponents()
            components.calendar = Calendar.current
            components.timeZone = TimeZone.current
            components.year = year
            components.month = month
            components.day = day
            components.hour = 12
            components.minute = 0
            date = components.date
        }

        let matchRange = match.range
        let prefix = (headerLine as NSString).substring(to: matchRange.location)
        let suffixStart = matchRange.location + matchRange.length
        let suffix = (headerLine as NSString).substring(from: suffixStart)

        var routine = "\(prefix) \(suffix)"
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",-:|"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let timeRange = parseTimeRange(in: routine),
           let range = routine.range(of: "\(twoDigit(timeRange.startHour)):\(twoDigit(timeRange.startMinute))-\(twoDigit(timeRange.endHour)):\(twoDigit(timeRange.endMinute))") {
            routine.removeSubrange(range)
            routine = routine.trimmingCharacters(in: CharacterSet(charactersIn: ",-:| "))
        }

        let routineNameRaw = routine.isEmpty ? nil : routine
        return (date, routineNameRaw)
    }

    func monthNumber(from month: String) -> Int? {
        switch month.prefix(3) {
        case "jan": return 1
        case "feb": return 2
        case "mar": return 3
        case "apr": return 4
        case "may": return 5
        case "jun": return 6
        case "jul": return 7
        case "aug": return 8
        case "sep": return 9
        case "oct": return 10
        case "nov": return 11
        case "dec": return 12
        default: return nil
        }
    }

    func parseTimeRange(in text: String) -> (startHour: Int, startMinute: Int, endHour: Int, endMinute: Int)? {
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = timeRangeRegex.firstMatch(in: text, options: [], range: range),
              let shRange = Range(match.range(at: 1), in: text),
              let smRange = Range(match.range(at: 2), in: text),
              let ehRange = Range(match.range(at: 3), in: text),
              let emRange = Range(match.range(at: 4), in: text),
              let startHour = Int(text[shRange]),
              let startMinute = Int(text[smRange]),
              let endHour = Int(text[ehRange]),
              let endMinute = Int(text[emRange]) else {
            return nil
        }

        return (startHour, startMinute, endHour, endMinute)
    }

    func mapTimeRangeToDate(_ range: (startHour: Int, startMinute: Int, endHour: Int, endMinute: Int), on date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current

        var startComponents = calendar.dateComponents(in: TimeZone.current, from: date)
        startComponents.hour = range.startHour
        startComponents.minute = range.startMinute
        startComponents.second = 0

        var endComponents = calendar.dateComponents(in: TimeZone.current, from: date)
        endComponents.hour = range.endHour
        endComponents.minute = range.endMinute
        endComponents.second = 0

        let start = calendar.date(from: startComponents) ?? date
        var end = calendar.date(from: endComponents) ?? date

        if end < start {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }

        return (start, end)
    }

    func likelyTimeRangeText(_ line: String) -> Bool {
        line.range(of: #"\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}"#, options: .regularExpression) != nil
    }

    func removeNumberPrefix(from line: String) -> String {
        line.replacingOccurrences(of: #"^\s*\d+\.\s*"#, with: "", options: .regularExpression)
    }

    struct ParsedStrengthResult {
        var strength: ParsedStrength
        var warnings: [String]
    }

    struct DescriptorToken {
        var setCount: Int
        var reps: Int
        var warning: String?
    }

    struct StrengthSetTemplate {
        var reps: Int
        var weight: (value: Double, unit: WeightUnit)?
        var restSeconds: Int?
    }

    func parseStrength(name: String, tail: String, defaultWeightUnit: WeightUnit) -> ParsedStrengthResult? {
        let perSide = parsePerSideWeight(in: tail)
        let base = parseBaseWeight(in: tail, defaultWeightUnit: defaultWeightUnit)

        let tokenParts = tail
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var templates: [StrengthSetTemplate] = []
        var pendingTemplateIndices: [Int] = []
        var currentRestSeconds: Int? = nil
        var descriptorWarnings: [String] = []

        for part in tokenParts {
            if let rest = parseRestSeconds(in: part) {
                currentRestSeconds = rest
                for index in templates.indices where templates[index].restSeconds == nil {
                    templates[index].restSeconds = rest
                }
            }

            let descriptors = allSetDescriptors(in: part)
            for descriptor in descriptors {
                if let warning = descriptor.warning {
                    descriptorWarnings.append("\(name): \(warning)")
                }
                for _ in 0..<descriptor.setCount {
                    templates.append(
                        StrengthSetTemplate(
                            reps: descriptor.reps,
                            weight: nil,
                            restSeconds: currentRestSeconds
                        )
                    )
                    pendingTemplateIndices.append(templates.count - 1)
                }
            }

            if let weight = parseWeight(in: part), !pendingTemplateIndices.isEmpty {
                for index in pendingTemplateIndices where templates[index].weight == nil {
                    templates[index].weight = weight
                }
                pendingTemplateIndices.removeAll()
            }
        }

        guard !templates.isEmpty else { return nil }

        var parsedSets: [ParsedStrengthSet] = []
        for template in templates {
            let chosenUnit = template.weight?.unit ?? perSide?.unit ?? base?.unit ?? defaultWeightUnit

            let totalWeight: Double?
            if let perSideValue = perSide?.value, let baseValue = base?.value {
                totalWeight = baseValue + (perSideValue * 2)
            } else if let templateWeight = template.weight {
                totalWeight = templateWeight.value
            } else if let baseValue = base?.value {
                totalWeight = baseValue
            } else {
                totalWeight = nil
            }

            parsedSets.append(
                ParsedStrengthSet(
                    reps: template.reps,
                    weight: totalWeight,
                    weightUnit: chosenUnit,
                    perSideWeight: perSide?.value,
                    baseWeight: base?.value,
                    isPerSide: perSide != nil && base != nil,
                    restSeconds: template.restSeconds
                )
            )
        }

        guard !parsedSets.isEmpty else { return nil }
        return ParsedStrengthResult(
            strength: ParsedStrength(
                exerciseNameRaw: name,
                sets: parsedSets,
                notes: descriptorWarnings.isEmpty ? nil : descriptorWarnings.joined(separator: " ")
            ),
            warnings: descriptorWarnings
        )
    }

    func parseCardio(name: String, tail: String) -> ParsedCardio? {
        let lowerName = name.lowercased()
        let lowerTail = tail.lowercased()

        let isCardioByKeyword = ["run", "running", "bike", "cycling", "swim", "walk", "treadmill", "indoor"]
            .contains(where: { lowerName.contains($0) || lowerTail.contains($0) })

        let distance = parseDistance(in: tail)
        let duration = parseDuration(in: tail)
        let pace = parsePace(in: tail)

        let hasCardioMetrics = distance != nil || duration != nil || pace != nil
        guard isCardioByKeyword && hasCardioMetrics else {
            return nil
        }

        let cardioSet = ParsedCardioSet(
            durationSeconds: duration,
            distance: distance?.value,
            distanceUnit: distance?.unit ?? .km,
            paceSeconds: pace
        )

        return ParsedCardio(exerciseNameRaw: name, sets: [cardioSet], notes: nil)
    }

    func allSetDescriptors(in text: String) -> [DescriptorToken] {
        var descriptors: [(range: NSRange, token: DescriptorToken)] = []
        descriptors += matches(for: nxrRegex, in: text).compactMap { match in
            guard let setCount = intCapture(match: match, index: 1, in: text),
                  let repsRaw = doubleCapture(match: match, index: 2, in: text) else {
                return nil
            }

            let flooredReps = Int(floor(repsRaw))
            let reps = max(1, flooredReps)
            let warning: String? = repsRaw == Double(reps) ? nil : "Fractional reps \(repsRaw) were floored to \(reps)."

            return (
                range: match.range,
                token: DescriptorToken(
                    setCount: setCount,
                    reps: reps,
                    warning: warning
                )
            )
        }

        descriptors += matches(for: setsOfRegex, in: text).compactMap { match in
            guard let setCount = intCapture(match: match, index: 1, in: text),
                  let reps = intCapture(match: match, index: 2, in: text) else {
                return nil
            }
            return (
                range: match.range,
                token: DescriptorToken(
                    setCount: setCount,
                    reps: reps,
                    warning: nil
                )
            )
        }

        return descriptors
            .sorted { $0.range.location < $1.range.location }
            .map(\.token)
    }

    func parsePerSideWeight(in text: String) -> (value: Double, unit: WeightUnit)? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(kg|kgs|kilogram|kilograms|lb|lbs|pound|pounds)\s*per\s*side"#
        guard let match = firstMatch(of: pattern, in: text, options: .caseInsensitive),
              let value = doubleCapture(match: match, index: 1, in: text),
              let unit = weightUnitCapture(match: match, index: 2, in: text) else {
            return nil
        }
        return (value, unit)
    }

    func parseBaseWeight(in text: String, defaultWeightUnit: WeightUnit) -> (value: Double, unit: WeightUnit)? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(kg|kgs|kilogram|kilograms|lb|lbs|pound|pounds)\s*bar"#
        guard let match = firstMatch(of: pattern, in: text, options: .caseInsensitive),
              let value = doubleCapture(match: match, index: 1, in: text),
              let unit = weightUnitCapture(match: match, index: 2, in: text) else {
            if containsBarToken(in: text) {
                return defaultWeightUnit == .kg ? (20, .kg) : (45, .lb)
            }
            return nil
        }
        return (value, unit)
    }

    func containsBarToken(in text: String) -> Bool {
        firstMatch(of: #"\bbar\b"#, in: text, options: .caseInsensitive) != nil
    }

    func parseWeight(in text: String) -> (value: Double, unit: WeightUnit)? {
        guard let match = matches(for: weightRegex, in: text).first,
              let value = doubleCapture(match: match, index: 1, in: text),
              let unit = weightUnitCapture(match: match, index: 2, in: text) else {
            return nil
        }
        return (value, unit)
    }

    func parseRestSeconds(in text: String) -> Int? {
        guard let match = matches(for: restRegex, in: text).first,
              let minutes = intCapture(match: match, index: 1, in: text),
              let seconds = intCapture(match: match, index: 2, in: text) else {
            return nil
        }
        return (minutes * 60) + seconds
    }

    func parseDistance(in text: String) -> (value: Double, unit: DistanceUnit)? {
        guard let match = matches(for: distanceRegex, in: text).first,
              let value = doubleCapture(match: match, index: 1, in: text),
              let unitRange = Range(match.range(at: 2), in: text) else {
            return nil
        }

        let unitToken = text[unitRange].lowercased()
        return (value, unitToken == "mi" ? .mi : .km)
    }

    func parseDuration(in text: String) -> Int? {
        if let match = matches(for: durationClockRegex, in: text).first,
           let minutes = intCapture(match: match, index: 1, in: text),
           let seconds = intCapture(match: match, index: 2, in: text) {
            return (minutes * 60) + seconds
        }

        if let match = matches(for: durationMinutesRegex, in: text).first,
           let minutes = intCapture(match: match, index: 1, in: text) {
            return minutes * 60
        }

        return nil
    }

    func parsePace(in text: String) -> Int? {
        if let match = matches(for: paceRegex, in: text).first,
           let minutes = intCapture(match: match, index: 1, in: text),
           let seconds = intCapture(match: match, index: 2, in: text) {
            return (minutes * 60) + seconds
        }

        let compactPattern = #"\b(\d{1,2}):(\d{2})(av|avg|pace)\b"#
        if let match = firstMatch(of: compactPattern, in: text, options: .caseInsensitive),
           let minutes = intCapture(match: match, index: 1, in: text),
           let seconds = intCapture(match: match, index: 2, in: text) {
            return (minutes * 60) + seconds
        }

        return nil
    }

    func generateImportHash(for text: String) -> String {
        let canonical = text
            .decomposedStringWithCompatibilityMapping
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9:]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func matches(for regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        return regex.matches(in: text, options: [], range: nsRange)
    }

    func firstMatch(of pattern: String, in text: String, options: NSRegularExpression.Options = []) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, options: [], range: range)
    }

    func intCapture(match: NSTextCheckingResult, index: Int, in text: String) -> Int? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }

    func doubleCapture(match: NSTextCheckingResult, index: Int, in text: String) -> Double? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return Double(text[range])
    }

    func weightUnitCapture(match: NSTextCheckingResult, index: Int, in text: String) -> WeightUnit? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        let token = text[range].lowercased()
        if token.hasPrefix("k") {
            return .kg
        }
        return .lb
    }

    func twoDigit(_ number: Int) -> String {
        String(format: "%02d", number)
    }
}

extension ExerciseType {
    var isCardio: Bool {
        switch self {
        case .run, .bike, .swim:
            return true
        default:
            return false
        }
    }
}
