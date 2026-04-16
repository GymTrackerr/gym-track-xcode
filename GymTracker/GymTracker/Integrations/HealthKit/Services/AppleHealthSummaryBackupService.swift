import Foundation
import SwiftData

@MainActor
final class AppleHealthSummaryBackupService {
    enum TransferError: LocalizedError {
        case missingUser
        case invalidSchemaVersion(Int)
        case invalidFile(String)
        case persistence(String)

        var errorDescription: String? {
            switch self {
            case .missingUser:
                return "You must be signed in to use Apple Health summary transfer."
            case .invalidSchemaVersion(let version):
                return "Unsupported Apple Health summary schema version: \(version)."
            case .invalidFile(let message):
                return message
            case .persistence(let message):
                return message
            }
        }
    }

    struct ImportReport {
        let inserted: Int
        let updated: Int
        let skipped: Int
        let totalImported: Int
        let warnings: [String]
    }

    private let modelContext: ModelContext
    private let currentUserProvider: () -> User?
    private let dateNormalizer: HealthKitDateNormalizer

    init(
        context: ModelContext,
        currentUserProvider: @escaping () -> User?,
        dateNormalizer: HealthKitDateNormalizer
    ) {
        self.modelContext = context
        self.currentUserProvider = currentUserProvider
        self.dateNormalizer = dateNormalizer
    }

    func exportAppleHealthSummaryJSON() throws -> URL {
        guard let user = currentUserProvider() else {
            throw TransferError.missingUser
        }

        let userId = user.id.uuidString
        let summaries = try fetchDailySummaries(userId: userId)
        let dayDTOs = summaries.map(AppleHealthSummaryDayDTO.init)

        let payload = AppleHealthSummaryPayloadDTO(dailySummaries: dayDTOs)
        let envelope = AppleHealthSummaryTransferEnvelope(
            version: 1,
            exportDate: Date(),
            dateRange: AppleHealthSummaryDateRangeDTO(from: dayDTOs),
            payload: payload
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(envelope)
            let fileURL = backupURL()
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            throw TransferError.persistence("Could not write Apple Health summary transfer file.")
        }
    }

    func importAppleHealthSummaryJSON(from url: URL) throws -> ImportReport {
        guard let user = currentUserProvider() else {
            throw TransferError.missingUser
        }

        let data = try readTransferData(from: url)
        let envelope = try decodeTransferEnvelope(from: data)

        guard envelope.version == 0 || envelope.version == 1 else {
            throw TransferError.invalidSchemaVersion(envelope.version)
        }

        var warnings: [String] = []
        let normalized = normalizeImportedDays(envelope.payload.dailySummaries, warnings: &warnings)
        let incomingByDayKey = Dictionary(uniqueKeysWithValues: normalized.map { ($0.dayKey, $0) })

        let userId = user.id.uuidString
        let existing = try fetchDailySummaries(userId: userId)
        var existingByDayKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.dayKey, $0) })

        var inserted = 0
        var updated = 0

        do {
            for day in incomingByDayKey.values.sorted(by: { $0.dayStart < $1.dayStart }) {
                if let existingSummary = existingByDayKey[day.dayKey] {
                    let isToday = dateNormalizer.sameDay(day.dayStart, Date())
                    existingSummary.dayStart = day.dayStart
                    existingSummary.steps = day.steps
                    existingSummary.activeEnergyKcal = day.activeEnergyKcal
                    existingSummary.restingEnergyKcal = day.restingEnergyKcal
                    existingSummary.exerciseMinutes = day.exerciseMinutes
                    existingSummary.standHours = day.standHours
                    existingSummary.moveGoalKcal = day.moveGoalKcal
                    existingSummary.exerciseGoalMinutes = day.exerciseGoalMinutes
                    existingSummary.standGoalHours = day.standGoalHours
                    existingSummary.sleepSeconds = day.sleepSeconds
                    existingSummary.bodyWeightKg = day.bodyWeightKg
                    existingSummary.schemaVersion = day.schemaVersion
                    existingSummary.lastRefreshedAt = day.lastRefreshedAt
                    existingSummary.isToday = isToday
                    existingSummary.isFullySynced = isToday ? false : day.isFullySynced
                    updated += 1
                } else {
                    let isToday = dateNormalizer.sameDay(day.dayStart, Date())
                    let summary = HealthKitDailyAggregateData(
                        userId: userId,
                        dayKey: day.dayKey,
                        dayStart: day.dayStart,
                        steps: day.steps,
                        activeEnergyKcal: day.activeEnergyKcal,
                        restingEnergyKcal: day.restingEnergyKcal,
                        exerciseMinutes: day.exerciseMinutes,
                        standHours: day.standHours,
                        moveGoalKcal: day.moveGoalKcal,
                        exerciseGoalMinutes: day.exerciseGoalMinutes,
                        standGoalHours: day.standGoalHours,
                        sleepSeconds: day.sleepSeconds,
                        bodyWeightKg: day.bodyWeightKg,
                        schemaVersion: day.schemaVersion,
                        lastRefreshedAt: day.lastRefreshedAt,
                        isToday: isToday,
                        isFullySynced: isToday ? false : day.isFullySynced
                    )
                    modelContext.insert(summary)
                    existingByDayKey[day.dayKey] = summary
                    inserted += 1
                }
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw TransferError.persistence("Could not import Apple Health summary transfer file.")
        }

        return ImportReport(
            inserted: inserted,
            updated: updated,
            skipped: warnings.count,
            totalImported: inserted + updated,
            warnings: warnings
        )
    }

    private func fetchDailySummaries(userId: String) throws -> [HealthKitDailyAggregateData] {
        let descriptor = FetchDescriptor<HealthKitDailyAggregateData>(
            predicate: #Predicate<HealthKitDailyAggregateData> { item in
                item.userId == userId
            },
            sortBy: [SortDescriptor(\.dayStart)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func readTransferData(from url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw TransferError.persistence("Could not read Apple Health summary transfer file.")
        }
    }

    private func decodeTransferEnvelope(from data: Data) throws -> AppleHealthSummaryTransferEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let envelope = try? decoder.decode(AppleHealthSummaryTransferEnvelope.self, from: data) {
            return envelope
        }

        if let legacyArray = try? decoder.decode([AppleHealthSummaryDayDTO].self, from: data) {
            return AppleHealthSummaryTransferEnvelope(
                version: 0,
                exportDate: Date(),
                dateRange: AppleHealthSummaryDateRangeDTO(from: legacyArray),
                payload: AppleHealthSummaryPayloadDTO(dailySummaries: legacyArray)
            )
        }

        throw TransferError.invalidFile("Apple Health summary transfer file format is invalid.")
    }

    private func normalizeImportedDays(
        _ days: [AppleHealthSummaryDayDTO],
        warnings: inout [String]
    ) -> [NormalizedSummary] {
        var seen = Set<String>()
        var normalized: [NormalizedSummary] = []

        for (index, dto) in days.enumerated() {
            guard let dayStart = resolvedDayStart(from: dto) else {
                warnings.append("Skipped record #\(index + 1): missing or invalid date.")
                continue
            }

            let trimmedDayKey = dto.dayKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            let dayKey = (trimmedDayKey?.isEmpty == false ? trimmedDayKey : nil)
                ?? dateNormalizer.dayKey(dayStart)

            if seen.contains(dayKey) {
                warnings.append("Skipped duplicate day \(dayKey).")
                continue
            }

            seen.insert(dayKey)

            normalized.append(NormalizedSummary(
                dayKey: dayKey,
                dayStart: dateNormalizer.startOfDay(dayStart),
                steps: max(0, dto.steps ?? 0),
                activeEnergyKcal: max(0, dto.activeEnergyKcal ?? 0),
                restingEnergyKcal: max(0, dto.restingEnergyKcal ?? 0),
                exerciseMinutes: max(0, dto.exerciseMinutes ?? 0),
                standHours: max(0, dto.standHours ?? 0),
                moveGoalKcal: max(0, dto.moveGoalKcal ?? 520),
                exerciseGoalMinutes: max(0, dto.exerciseGoalMinutes ?? 30),
                standGoalHours: max(0, dto.standGoalHours ?? 12),
                sleepSeconds: max(0, dto.sleepSeconds ?? 0),
                bodyWeightKg: max(0, dto.bodyWeightKg ?? 0),
                schemaVersion: dto.summarySchemaVersion ?? HealthKitDailyAggregateData.currentSchemaVersion,
                lastRefreshedAt: dto.lastRefreshedAt ?? .distantPast,
                isFullySynced: dto.isFullySynced ?? false
            ))
        }

        return normalized
    }

    private func resolvedDayStart(from dto: AppleHealthSummaryDayDTO) -> Date? {
        if let dayStart = dto.dayStart {
            return dayStart
        }

        guard let dayKey = dto.dayKey?.trimmingCharacters(in: .whitespacesAndNewlines), !dayKey.isEmpty else {
            return nil
        }

        return Self.dayKeyFormatter.date(from: dayKey)
    }

    private func backupURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileName = "apple-health-summary-backup-\(stamp).json"

        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documents.appendingPathComponent(fileName)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct NormalizedSummary {
    let dayKey: String
    let dayStart: Date
    let steps: Double
    let activeEnergyKcal: Double
    let restingEnergyKcal: Double
    let exerciseMinutes: Double
    let standHours: Int
    let moveGoalKcal: Double
    let exerciseGoalMinutes: Double
    let standGoalHours: Int
    let sleepSeconds: Double
    let bodyWeightKg: Double
    let schemaVersion: Double
    let lastRefreshedAt: Date
    let isFullySynced: Bool
}

private struct AppleHealthSummaryTransferEnvelope: Codable {
    let version: Int
    let exportDate: Date
    let dateRange: AppleHealthSummaryDateRangeDTO
    let payload: AppleHealthSummaryPayloadDTO

    enum CodingKeys: String, CodingKey {
        case version
        case schemaVersion
        case exportDate
        case exportedAt
        case dateRange
        case payload
        case dailySummaries
        case summaries
    }

    init(
        version: Int,
        exportDate: Date,
        dateRange: AppleHealthSummaryDateRangeDTO,
        payload: AppleHealthSummaryPayloadDTO
    ) {
        self.version = version
        self.exportDate = exportDate
        self.dateRange = dateRange
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version)
            ?? container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? 0
        let decodedExportDate = try container.decodeIfPresent(Date.self, forKey: .exportDate)
            ?? container.decodeIfPresent(Date.self, forKey: .exportedAt)
            ?? Date()

        let decodedPayload: AppleHealthSummaryPayloadDTO
        if let payload = try container.decodeIfPresent(AppleHealthSummaryPayloadDTO.self, forKey: .payload) {
            decodedPayload = payload
        } else if let summaries = try container.decodeIfPresent([AppleHealthSummaryDayDTO].self, forKey: .dailySummaries) {
            decodedPayload = AppleHealthSummaryPayloadDTO(dailySummaries: summaries)
        } else if let summaries = try container.decodeIfPresent([AppleHealthSummaryDayDTO].self, forKey: .summaries) {
            decodedPayload = AppleHealthSummaryPayloadDTO(dailySummaries: summaries)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .payload,
                in: container,
                debugDescription: "Missing payload or daily summaries."
            )
        }

        let decodedRange = try container.decodeIfPresent(AppleHealthSummaryDateRangeDTO.self, forKey: .dateRange)
            ?? AppleHealthSummaryDateRangeDTO(from: decodedPayload.dailySummaries)

        version = decodedVersion
        exportDate = decodedExportDate
        dateRange = decodedRange
        payload = decodedPayload
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(exportDate, forKey: .exportDate)
        try container.encode(dateRange, forKey: .dateRange)
        try container.encode(payload, forKey: .payload)
    }
}

private struct AppleHealthSummaryDateRangeDTO: Codable {
    let startDayKey: String?
    let endDayKey: String?
    let startDate: Date?
    let endDate: Date?
    let totalDays: Int

    init(from summaries: [AppleHealthSummaryDayDTO]) {
        let resolved = summaries.compactMap { dto -> (String, Date)? in
            if let dayStart = dto.dayStart {
                let dayKey = dto.dayKey ?? Self.dayKeyFormatter.string(from: dayStart)
                return (dayKey, dayStart)
            }
            guard
                let dayKey = dto.dayKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                !dayKey.isEmpty,
                let dayStart = Self.dayKeyFormatter.date(from: dayKey)
            else {
                return nil
            }
            return (dayKey, dayStart)
        }.sorted { $0.1 < $1.1 }

        startDayKey = resolved.first?.0
        endDayKey = resolved.last?.0
        startDate = resolved.first?.1
        endDate = resolved.last?.1
        totalDays = resolved.count
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct AppleHealthSummaryPayloadDTO: Codable {
    let dailySummaries: [AppleHealthSummaryDayDTO]
}

private struct AppleHealthSummaryDayDTO: Codable {
    let dayKey: String?
    let dayStart: Date?
    let steps: Double?
    let activeEnergyKcal: Double?
    let restingEnergyKcal: Double?
    let exerciseMinutes: Double?
    let standHours: Int?
    let moveGoalKcal: Double?
    let exerciseGoalMinutes: Double?
    let standGoalHours: Int?
    let sleepSeconds: Double?
    let bodyWeightKg: Double?
    let summarySchemaVersion: Double?
    let lastRefreshedAt: Date?
    let isFullySynced: Bool?

    enum CodingKeys: String, CodingKey {
        case dayKey
        case dateKey
        case dayStart
        case date
        case startDate
        case steps
        case stepCount
        case activeEnergyKcal
        case activeEnergy
        case restingEnergyKcal
        case restingEnergy
        case exerciseMinutes
        case appleExerciseMinutes
        case standHours
        case moveGoalKcal
        case moveGoal
        case exerciseGoalMinutes
        case exerciseGoal
        case standGoalHours
        case standGoal
        case sleepSeconds
        case sleepDurationSeconds
        case bodyWeightKg
        case weightKg
        case summarySchemaVersion
        case schemaVersion
        case lastRefreshedAt
        case isFullySynced
    }

    init(_ summary: HealthKitDailyAggregateData) {
        dayKey = summary.dayKey
        dayStart = summary.dayStart
        steps = summary.steps
        activeEnergyKcal = summary.activeEnergyKcal
        restingEnergyKcal = summary.restingEnergyKcal
        exerciseMinutes = summary.exerciseMinutes
        standHours = summary.standHours
        moveGoalKcal = summary.moveGoalKcal
        exerciseGoalMinutes = summary.exerciseGoalMinutes
        standGoalHours = summary.standGoalHours
        sleepSeconds = summary.sleepSeconds
        bodyWeightKg = summary.bodyWeightKg
        summarySchemaVersion = summary.schemaVersion
        lastRefreshedAt = summary.lastRefreshedAt
        isFullySynced = summary.isFullySynced
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        dayKey = try container.decodeIfPresent(String.self, forKey: .dayKey)
            ?? container.decodeIfPresent(String.self, forKey: .dateKey)
        dayStart = try container.decodeIfPresent(Date.self, forKey: .dayStart)
            ?? container.decodeIfPresent(Date.self, forKey: .date)
            ?? container.decodeIfPresent(Date.self, forKey: .startDate)
        steps = try container.decodeIfPresent(Double.self, forKey: .steps)
            ?? container.decodeIfPresent(Double.self, forKey: .stepCount)
        activeEnergyKcal = try container.decodeIfPresent(Double.self, forKey: .activeEnergyKcal)
            ?? container.decodeIfPresent(Double.self, forKey: .activeEnergy)
        restingEnergyKcal = try container.decodeIfPresent(Double.self, forKey: .restingEnergyKcal)
            ?? container.decodeIfPresent(Double.self, forKey: .restingEnergy)
        exerciseMinutes = try container.decodeIfPresent(Double.self, forKey: .exerciseMinutes)
            ?? container.decodeIfPresent(Double.self, forKey: .appleExerciseMinutes)
        standHours = try container.decodeIfPresent(Int.self, forKey: .standHours)
        moveGoalKcal = try container.decodeIfPresent(Double.self, forKey: .moveGoalKcal)
            ?? container.decodeIfPresent(Double.self, forKey: .moveGoal)
        exerciseGoalMinutes = try container.decodeIfPresent(Double.self, forKey: .exerciseGoalMinutes)
            ?? container.decodeIfPresent(Double.self, forKey: .exerciseGoal)
        standGoalHours = try container.decodeIfPresent(Int.self, forKey: .standGoalHours)
            ?? container.decodeIfPresent(Int.self, forKey: .standGoal)
        sleepSeconds = try container.decodeIfPresent(Double.self, forKey: .sleepSeconds)
            ?? container.decodeIfPresent(Double.self, forKey: .sleepDurationSeconds)
        bodyWeightKg = try container.decodeIfPresent(Double.self, forKey: .bodyWeightKg)
            ?? container.decodeIfPresent(Double.self, forKey: .weightKg)
        summarySchemaVersion = try container.decodeIfPresent(Double.self, forKey: .summarySchemaVersion)
            ?? container.decodeIfPresent(Double.self, forKey: .schemaVersion)
        lastRefreshedAt = try container.decodeIfPresent(Date.self, forKey: .lastRefreshedAt)
        isFullySynced = try container.decodeIfPresent(Bool.self, forKey: .isFullySynced)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(dayKey, forKey: .dayKey)
        try container.encodeIfPresent(dayStart, forKey: .dayStart)
        try container.encodeIfPresent(steps, forKey: .steps)
        try container.encodeIfPresent(activeEnergyKcal, forKey: .activeEnergyKcal)
        try container.encodeIfPresent(restingEnergyKcal, forKey: .restingEnergyKcal)
        try container.encodeIfPresent(exerciseMinutes, forKey: .exerciseMinutes)
        try container.encodeIfPresent(standHours, forKey: .standHours)
        try container.encodeIfPresent(moveGoalKcal, forKey: .moveGoalKcal)
        try container.encodeIfPresent(exerciseGoalMinutes, forKey: .exerciseGoalMinutes)
        try container.encodeIfPresent(standGoalHours, forKey: .standGoalHours)
        try container.encodeIfPresent(sleepSeconds, forKey: .sleepSeconds)
        try container.encodeIfPresent(bodyWeightKg, forKey: .bodyWeightKg)
        try container.encodeIfPresent(summarySchemaVersion, forKey: .summarySchemaVersion)
        try container.encodeIfPresent(lastRefreshedAt, forKey: .lastRefreshedAt)
        try container.encodeIfPresent(isFullySynced, forKey: .isFullySynced)
    }
}
