import XCTest
@testable import Clutch

/// Clue's download is a password-locked zip. These fixtures hold a small
/// Clue-shaped measurements.json (7 period days, 3 cycles) zipped plainly,
/// with ZipCrypto (macOS `zip -P`), and with WinZip AES-256. Password:
/// "clue-pass".
final class ZipReaderTests: XCTestCase {
    private let plain = Data(base64Encoded: "UEsDBAoAAAAAAKF4dF0AAAAAAAAAAAAAAAARABwAQ2x1ZURhdGFEb3dubG9hZC9VVAkAA+2nAGvtpwBrdXgLAAEE9QEAAAQAAAAAUEsDBBQAAAAIAKF4dF1iL5+fVgEAACJlAAAiABwAQ2x1ZURhdGFEb3dubG9hZC9tZWFzdXJlbWVudHMuanNvblVUCQAD7acAa+2nAGt1eAsAAQT1AQAABAAAAADt01FLwlAYgOG/IrtWsElJ/Y0uQ2K0E4x0G+5oifjf25SwcJChV/HAbvad8X67OM/TNombOiQPg6QOy6LKk+EgKfLuPR2nt6PxTft0szyL4XS6zuarbrxNqjoWVdl9sQh5sVoku91wcEY87Y2n14lPeuOTq8TT+774YXpxfDLuix+mF8bTUXp3Gv+aXh6f9sanf4tnRXlM17/fv6fvycOvPb8ss0XddF+FjxjKuF/chHV7Gjf71cU8bxfPfqwuqxia4+7ynOsZ2wXd+WNchqZ5Xc0H7yG8nXtJ8cILL7zwwgsvvPDCCy+88MILL7zwwgsvvPDCCy+88MILL7zwwgsvvPDCCy+88MILL7zwwgsvvPDCCy+88MILL7zwwgsvvPDCCy+88MILL7zwwgsvvPDCCy+88MILL7zwwgsvvPDCCy+88MILL7zwwgsvvPDCCy+8/jev2SdQSwECHgMKAAAAAACheHRdAAAAAAAAAAAAAAAAEQAYAAAAAAAAABAA7UEAAAAAQ2x1ZURhdGFEb3dubG9hZC9VVAUAA+2nAGt1eAsAAQT1AQAABAAAAABQSwECHgMUAAAACACheHRdYi+fn1YBAAAiZQAAIgAYAAAAAAABAAAApIFLAAAAQ2x1ZURhdGFEb3dubG9hZC9tZWFzdXJlbWVudHMuanNvblVUBQAD7acAa3V4CwABBPUBAAAEAAAAAFBLBQYAAAAAAgACAL8AAAD9AQAAAAA=")!
    private let zipCrypto = Data(base64Encoded: "UEsDBAoAAAAAAKF4dF0AAAAAAAAAAAAAAAARABwAQ2x1ZURhdGFEb3dubG9hZC9VVAkAA+2nAGvtpwBrdXgLAAEE9QEAAAQAAAAAUEsDBBQACQAIAKF4dF1iL5+fYgEAACJlAAAiABwAQ2x1ZURhdGFEb3dubG9hZC9tZWFzdXJlbWVudHMuanNvblVUCQAD7acAa+2nAGt1eAsAAQT1AQAABAAAAAChCnbn6BkfNzVAyBnoYlvEE4iwoGpO9OA3asVIqSoOMz8y9HeCnbN/M58C6BqvZNgJ6zQlkcepb8G/9SHOYgnP+VBYehhyawAwQPfv6crf6poqJZ22+IdRMV+GGFuanuODr7cPS88easHDVYJvIs0IC9iQU8EtYRhZJEfOwTFCV+PRBs/R2RMJu/bQ6PViXGKScoh4kDnFsEuFvIKYjBtnlBiUsx9x2paQI8NiwPmv6y4OEhKe9VgwbYdkX2Qi8Trxq2bzxm/KZiqLFI8TWa2esByc1ZWZNLH+taxYUSKl28rlahRWi32T23RGJz8a7d1f1n78943395+MOqPLws8lHzfyLqqzJ1RK6Catt2tA+p3SJdWUI+lG4BGb8oSKhoOw1BdyaqlN2RjfNsqox2/FLxpqnqQ/PgqAGrYZSK5UBKIity9XQe9tqiQb489PJsI90lx2cp5YhCBBGPztHenwTzJQSwcIYi+fn2IBAAAiZQAAUEsBAh4DCgAAAAAAoXh0XQAAAAAAAAAAAAAAABEAGAAAAAAAAAAQAO1BAAAAAENsdWVEYXRhRG93bmxvYWQvVVQFAAPtpwBrdXgLAAEE9QEAAAQAAAAAUEsBAh4DFAAJAAgAoXh0XWIvn59iAQAAImUAACIAGAAAAAAAAQAAAKSBSwAAAENsdWVEYXRhRG93bmxvYWQvbWVhc3VyZW1lbnRzLmpzb25VVAUAA+2nAGt1eAsAAQT1AQAABAAAAABQSwUGAAAAAAIAAgC/AAAAGQIAAAAA")!
    private let aes = Data(base64Encoded: "UEsDBDMAAQBjAAAAIQAAAAAAcgEAACJlAAAiAAsAQ2x1ZURhdGFEb3dubG9hZC9tZWFzdXJlbWVudHMuanNvbgGZBwACAEFFAwgAMeKk5OWBzebi6QfVdoC5KVy9Kqw/498Vwgxcr3K6ewt6ACPfKUl3b+mgFdiZm4KXJ1LLFfpfIJOp10XoItlSi1sc5BMFXX+bRKP1pHjaB5oR3cH1uwQWmbojxfCLvOdISReleWaXKx0TM0BgJ7u+Z5ycFtgQlGzQtnIIZJI9MeGHdtBL7e2T/74iuaMPy+2jtkl0FJCloXgVWa3s3pggsMdM5oIHBqqnlTvkekbPPW0FrZu3n24f/Nn/Uqg9n7Nmld/r4lGJQTJw/OvZ9E1LYoQIMAkLJQAwyeQzXwfeR60zgp7dGoZPiegKL3E2CEfv3cGYFlsxBWpWgcLrAYtOVVxz8BWLrr1mTt6MMzUvlr+gLoeUkzlxQ2LIPeQ2/h7V3N4+KP7NvfkhZlxkUqNip9F7u4A6zsAckVxMyzQhODSAuJSp+pravraJHbLTzrHrVFXUj9brHT3OTo0qE+MoZ5+kXV5hk2T+xuNc40CWLSpbwVBLAQIzADMAAQBjAAAAIQAAAAAAcgEAACJlAAAiAAsAAAAAAAAAAAAAAAAAAABDbHVlRGF0YURvd25sb2FkL21lYXN1cmVtZW50cy5qc29uAZkHAAIAQUUDCABQSwUGAAAAAAEAAQBbAAAAvQEAAAAA")!

    private func periodDays(_ days: [ImportedDay]) -> Int {
        days.filter { $0.flow?.isBleeding == true }.count
    }

    func testPlainZip() throws {
        XCTAssertEqual(periodDays(try ClueImport.days(from: plain)), 7)
    }

    func testZipCryptoAsksThenOpens() throws {
        XCTAssertThrowsError(try ClueImport.days(from: zipCrypto)) { XCTAssertEqual($0 as? ZipReader.Failure, .needsPassword) }
        XCTAssertThrowsError(try ClueImport.days(from: zipCrypto, password: "nope")) { XCTAssertEqual($0 as? ZipReader.Failure, .wrongPassword) }
        XCTAssertEqual(periodDays(try ClueImport.days(from: zipCrypto, password: "clue-pass")), 7)
    }

    func testAESAsksThenOpens() throws {
        XCTAssertThrowsError(try ClueImport.days(from: aes)) { XCTAssertEqual($0 as? ZipReader.Failure, .needsPassword) }
        XCTAssertThrowsError(try ClueImport.days(from: aes, password: "nope")) { XCTAssertEqual($0 as? ZipReader.Failure, .wrongPassword) }
        let days = try ClueImport.days(from: aes, password: "clue-pass")
        XCTAssertEqual(periodDays(days), 7)
        XCTAssertTrue(days.contains { $0.symptoms.contains("cramps") })
    }

    func testNotAZipIsParsedAsJSON() throws {
        let json = #"[{"type":"period","date":"2025-01-01","value":{"option":"light"}}]"#
        XCTAssertEqual(periodDays(try ClueImport.days(from: Data(json.utf8))), 1)
    }
}
