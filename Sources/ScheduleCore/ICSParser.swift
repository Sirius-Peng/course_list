import Foundation

public struct ICSParser {
    private struct Property {
        var name: String
        var parameters: [String: String]
        var value: String
    }
    public init() {}
    public func parse(_ text: String) throws -> [CourseOccurrence] {
        guard text.utf8.count <= 4_000_000 else { throw ScheduleError.invalid("ICS 文件超过 4 MB") }
        let unfolded = unfold(text)
        guard unfolded.contains("BEGIN:VCALENDAR"), unfolded.contains("END:VCALENDAR") else {
            throw ScheduleError.invalid("文件不是有效的 ICS 日历")
        }
        var events: [[Property]] = [], current: [Property]? = nil
        for line in unfolded {
            if line == "BEGIN:VEVENT" {
                guard current == nil else { throw ScheduleError.invalid("VEVENT 嵌套无效") }
                current = []
            } else if line == "END:VEVENT" {
                guard let event = current else { throw ScheduleError.invalid("VEVENT 缺少起始标记") }
                events.append(event); current = nil
            } else if current != nil, let p = property(line) { current?.append(p) }
        }
        guard current == nil, events.count <= 5000 else { throw ScheduleError.invalid("ICS 事件未闭合或数量过多") }
        var result: [CourseOccurrence] = []
        for event in events {
            func first(_ name: String) -> Property? { event.first { $0.name == name } }
            if first("RECURRENCE-ID") != nil {
                throw ScheduleError.invalid("此文件包含重复课程的单次修改，请导入已展开的 ICS 课表")
            }
            if first("STATUS")?.value.uppercased() == "CANCELLED" { continue }
            guard let startProp = first("DTSTART") else { throw ScheduleError.invalid("课程缺少 DTSTART") }
            if startProp.parameters["VALUE"] == "DATE" || startProp.value.count == 8 { continue }
            let title = decode(first("SUMMARY")?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let endProp = first("DTEND") else { throw ScheduleError.invalid("课程缺少名称或结束时间") }
            let start = try date(startProp), end = try date(endProp)
            let duration = end.timeIntervalSince(start)
            guard duration > 0, duration <= 86400 else { throw ScheduleError.invalid("课程结束时间早于开始时间或超过一天") }
            let location = decode(first("LOCATION")?.value ?? ""), notes = decode(first("DESCRIPTION")?.value ?? "")
            var starts = try recurrenceStarts(first("RRULE"), start: start, property: startProp)
            for p in event where p.name == "RDATE" {
                for value in p.value.split(separator: ",") {
                    guard !value.contains("/") else { throw ScheduleError.invalid("暂未支持 RDATE 时间区间") }
                    starts.insert(try date(Property(name: p.name, parameters: p.parameters, value: String(value))))
                }
            }
            for p in event where p.name == "EXDATE" {
                for value in p.value.split(separator: ",") {
                    starts.remove(try date(Property(name: p.name, parameters: p.parameters, value: String(value))))
                }
            }
            for d in starts {
                result.append(CourseOccurrence(title: title, location: location, start: d, end: d.addingTimeInterval(duration), notes: notes))
            }
            guard result.count <= 5000 else { throw ScheduleError.invalid("展开后课程超过 5000 条") }
        }
        return Array(Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values)
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
    private func unfold(_ text: String) -> [String] {
        let lines = text.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var result: [String] = []
        for line in lines {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !result.isEmpty { result[result.count - 1] += String(line.dropFirst()) }
            else { result.append(line) }
        }
        return result
    }
    private func property(_ line: String) -> Property? {
        var quoted = false
        guard let colon = line.indices.first(where: { index in
            if line[index] == "\"" { quoted.toggle() }
            return line[index] == ":" && !quoted
        }) else { return nil }
        let head = line[..<colon].components(separatedBy: ";")
        var parameters: [String: String] = [:]
        for item in head.dropFirst() {
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { parameters[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return Property(name: head[0].uppercased(), parameters: parameters, value: String(line[line.index(after: colon)...]))
    }
    private func date(_ p: Property) throws -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.isLenient = false
        f.calendar = Calendar(identifier: .gregorian)
        if p.value.hasSuffix("Z") { f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'" }
        else {
            let zone = p.parameters["TZID"] ?? "Asia/Shanghai"
            guard let tz = TimeZone(identifier: zone) else { throw ScheduleError.invalid("未知课程时区：\(zone)") }
            f.timeZone = tz; f.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        guard let date = f.date(from: p.value), f.string(from: date) == p.value else { throw ScheduleError.invalid("无效课程日期：\(p.value)") }
        return date
    }
    private func recurrenceStarts(_ rule: Property?, start: Date, property startProp: Property) throws -> Set<Date> {
        guard let rule else { return [start] }
        var fields: [String: String] = [:]
        for part in rule.value.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, fields[pair[0]] == nil else { throw ScheduleError.invalid("重复规则格式无效") }
            fields[pair[0]] = pair[1]
        }
        let allowed: Set<String> = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "WKST"]
        guard Set(fields.keys).isSubset(of: allowed), let freq = fields["FREQ"], ["DAILY", "WEEKLY"].contains(freq),
              fields["WKST"] == nil || fields["WKST"] == "MO", freq != "DAILY" || fields["BYDAY"] == nil else {
            throw ScheduleError.invalid("此重复规则尚未支持，请导入按日期展开的课表")
        }
        let interval = Int(fields["INTERVAL"] ?? "1") ?? 0
        let count = fields["COUNT"].flatMap(Int.init)
        guard interval > 0, interval <= 52, fields["COUNT"] == nil || (count != nil && count! > 0 && count! <= 5000),
              !(fields["COUNT"] != nil && fields["UNTIL"] != nil), count != nil || fields["UNTIL"] != nil else {
            throw ScheduleError.invalid("重复课程需要有效的 COUNT 或 UNTIL")
        }
        let until: Date? = try fields["UNTIL"].map { try date(Property(name: "UNTIL", parameters: startProp.parameters, value: $0)) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = startProp.value.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0)! : TimeZone(identifier: startProp.parameters["TZID"] ?? "Asia/Shanghai")!
        let dayCodes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        let byDay = fields["BYDAY"]?.split(separator: ",").map(String.init) ?? []
        guard byDay.allSatisfy({ dayCodes[$0] != nil }) else { throw ScheduleError.invalid("重复规则 BYDAY 无效") }
        let weekdays = byDay.isEmpty ? [cal.component(.weekday, from: start)] : byDay.compactMap { dayCodes[$0] }
        let weekdayOffset = (cal.component(.weekday, from: start) + 5) % 7
        var dates: Set<Date> = []
        for day in 0...370 {
            let candidate = cal.date(byAdding: .day, value: day, to: start)!
            if let until, candidate > until { return dates }
            let matches = freq == "DAILY" ? day % interval == 0 : ((day + weekdayOffset) / 7) % interval == 0 && weekdays.contains(cal.component(.weekday, from: candidate))
            if matches {
                dates.insert(candidate)
                if let count, dates.count == count { return dates }
            }
        }
        throw ScheduleError.invalid("重复课程超出一年，请缩小学期范围")
    }
    private func decode(_ text: String) -> String {
        var output = "", escaped = false
        for c in text {
            if escaped { output.append(c == "n" || c == "N" ? "\n" : c); escaped = false }
            else if c == "\\" { escaped = true }
            else { output.append(c) }
        }
        if escaped { output.append("\\") }
        return output
    }
}
