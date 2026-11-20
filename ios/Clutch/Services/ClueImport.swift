import Foundation

/// Reads a period-tracker export into `ImportedDay`s. Built for Clue's
/// data download (Clue › Settings › Download my data: a zip holding
/// `measurements.json`, a list of `{"type", "date", "value"}` records such
/// as `{"type": "period", "date": "2025-06-21", "value": {"option":
/// "heavy"}}`), but forgiving, since export formats change:
///
/// - JSON, as a list of days (`{"day": "2023-01-02", "period": "medium",
///   "pain": ["cramps"]}`), a list of measurements (`{"date": …, "type":
///   "period", "value": {"option": "heavy"}}`), or either one wrapped in an
///   object (`{"data": [...]}`, `{"measurements": [...]}`).
/// - CSV with a date column and a period/flow/bleeding column.
///
/// Anything it doesn't recognise is skipped rather than guessed at.
enum ClueImport {
    enum Failure: Error, Equatable {
        case unreadable
        case noPeriodData
    }

    static func parse(_ data: Data) throws -> [ImportedDay] {
        let days: [ImportedDay]
        if let json = try? JSONSerialization.jsonObject(with: data) {
            days = parseJSON(json)
        } else if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            days = parseCSV(text)
        } else {
            throw Failure.unreadable
        }
        guard days.contains(where: { $0.flow?.isBleeding == true || $0.periodStart }) else {
            throw Failure.noPeriodData
        }
        return days
    }

    // MARK: JSON

    private static func parseJSON(_ json: Any) -> [ImportedDay] {
        let records = recordList(in: json)
        var byDay: [String: ImportedDay] = [:]
        for record in records {
            guard let (key, date) = dateOf(record) else { continue }
            var day = byDay[key] ?? ImportedDay(date: date)
            if let type = record["type"] as? String {
                // Clue's measurements.json: only the types Clutch tracks.
                // Notes, tags, medication and the rest are left alone, so
                // a note like "stressful week" isn't read as a symptom.
                guard Self.measurementTypes.contains(type.lowercased()) else { continue }
                apply(category: type, value: record["value"], to: &day)
            } else {
                for (field, value) in record where !dateKeys.contains(field.lowercased()) {
                    apply(category: field, value: value, to: &day)
                }
            }
            byDay[key] = day
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// The biggest list of objects anywhere in the file.
    private static func recordList(in json: Any) -> [[String: Any]] {
        if let list = json as? [[String: Any]] { return list }
        if let object = json as? [String: Any] {
            return object.values.map(recordList).max { $0.count < $1.count } ?? []
        }
        return []
    }

    /// Clue's measurement types that map onto Clutch: bleeding, and the
    /// feelings and symptoms in Clutch's catalog.
    static let measurementTypes: Set<String> = [
        "period", "bleeding", "flow", "menstruation", "pain", "feelings", "emotion", "emotions",
        "mind", "digestion", "craving", "cravings", "sleep_quality", "sleep",
    ]

    private static let dateKeys: Set<String> = ["day", "date", "timestamp", "start", "starttime", "start_date"]

    private static func dateOf(_ record: [String: Any]) -> (String, Date)? {
        for (field, value) in record where dateKeys.contains(field.lowercased()) {
            if let string = value as? String, let parsed = parseDate(string) { return parsed }
        }
        return nil
    }

    // MARK: CSV

    private static func parseCSV(_ text: String) -> [ImportedDay] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first else { return [] }
        let separator: Character = header.contains(";") && !header.contains(",") ? ";" : ","
        let columns = header.split(separator: separator, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces.union(["\""])).lowercased() }
        guard let dateColumn = columns.firstIndex(where: dateKeys.contains) else { return [] }

        var byDay: [String: ImportedDay] = [:]
        for line in lines.dropFirst() {
            let cells = line.split(separator: separator, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces.union(["\""])) }
            guard cells.count > dateColumn, let (key, date) = parseDate(cells[dateColumn]) else { continue }
            var day = byDay[key] ?? ImportedDay(date: date)
            for (i, cell) in cells.enumerated() where i != dateColumn && i < columns.count && !cell.isEmpty {
                apply(category: columns[i], value: cell, to: &day)
            }
            byDay[key] = day
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    // MARK: Mapping

    /// Turns one field ("period": "heavy", "pain": ["cramps"], …) into flow
    /// and symptoms.
    static func apply(category: String, value: Any?, to day: inout ImportedDay) {
        let category = category.lowercased()
        let options = flatten(value)

        if ["period", "bleeding", "flow", "menstruation", "menstrual_flow"].contains(where: category.contains) {
            for option in options {
                if let flow = flow(from: option), flow.rank > (day.flow?.rank ?? -1) { day.flow = flow }
                if option.contains("start") || option.contains("first") { day.periodStart = true }
            }
            return
        }
        if category.contains("craving") && !options.isEmpty {
            day.symptoms.insert("cravings")
        }
        if category.contains("sleep") {
            for option in options where ["0-3", "3-6", "poor", "bad", "insomnia", "restless", "trouble"].contains(where: option.contains) {
                day.symptoms.insert("poor-sleep")
            }
        }
        // Energy levels ("low", "exhausted") aren't feelings.
        guard !category.contains("energy") else { return }
        for option in options + [category] {
            if let symptom = symptom(from: option) { day.symptoms.insert(symptom) }
        }
    }

    static func flow(from option: String) -> Flow? {
        let option = option.lowercased()
        if option.contains("heavy") { return .heavy }
        if option.contains("medium") || option.contains("moderate") || option == "true" || option == "yes" || option == "1" { return .medium }
        if option.contains("light") || option.contains("spotting") { return .light }
        if option.contains("none") || option == "false" || option == "no" { return .noFlow }
        return nil
    }

    private static func symptom(from option: String) -> String? {
        let option = option.lowercased()
        let table: [(words: [String], id: String)] = [
            (["cramp", "period_pain", "abdominal"], "cramps"),
            (["headache", "migraine"], "headache"),
            (["bloat"], "bloating"),
            (["anxious", "anxiety"], "anxious"),
            (["sad", "depress", "feeling_low", "feeling low"], "low"),
            (["irritab", "angry", "anger"], "irritable"),
            (["stress"], "stressed"),
        ]
        if option == "low" { return "low" }
        return table.first { $0.words.contains(where: option.contains) }?.id
    }

    /// Strings out of whatever shape a value comes in: "x", ["x", "y"],
    /// {"option": "x"}, [{"option": "x"}], true.
    private static func flatten(_ value: Any?) -> [String] {
        switch value {
        case let string as String: return [string.lowercased()]
        case let bool as Bool: return [bool ? "true" : "false"]
        case let number as NSNumber: return [number.stringValue]
        case let list as [Any]: return list.flatMap(flatten)
        case let object as [String: Any]:
            for key in ["option", "value", "name", "type"] {
                if let inner = object[key] { return flatten(inner) }
            }
            return object.values.flatMap(flatten)
        default: return []
        }
    }

    // MARK: Dates

    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    /// A day key and the local-midnight date for it. Times are ignored: a
    /// tracker's day is the calendar day it was logged for.
    static func parseDate(_ string: String) -> (String, Date)? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 10 else { return nil }
        let key = String(trimmed.prefix(10)).replacingOccurrences(of: "/", with: "-")
        guard let date = isoDay.date(from: key) else { return nil }
        return (key, date)
    }
}

extension ClueImport {
    /// The file inside a picked folder (Clue's unzipped
    /// `ClueDataDownload-…`), or the picked file itself.
    static func dataFile(in url: URL) -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return url }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
            if file.lastPathComponent.lowercased() == "measurements.json" { return file }
        }
        return url
    }
}

extension ClueImport {
    /// The picked file as bytes: a folder's `measurements.json`, or the
    /// file itself (a zip, JSON or CSV). Read while access is open.
    static func readPicked(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: dataFile(in: url))
    }

    /// Days from what she picked. Clue's download is a password-locked zip;
    /// without the password this throws `ZipReader.Failure.needsPassword`
    /// so the screen can ask for it.
    static func days(from data: Data, password: String? = nil) throws -> [ImportedDay] {
        guard ZipReader.isZip(data) else { return try parse(data) }
        let entries = try ZipReader.entries(data)
        let file = entries.first { ($0.name as NSString).lastPathComponent.lowercased() == "measurements.json" }
            ?? entries.first { ["json", "csv"].contains(($0.name as NSString).pathExtension.lowercased()) }
        guard let file else { throw Failure.noPeriodData }
        return try parse(ZipReader.extract(file, from: data, password: password))
    }
}
