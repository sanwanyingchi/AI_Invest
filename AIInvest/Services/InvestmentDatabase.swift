import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case statementFailed(String)
    case bindingFailed(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): "无法打开本地数据库：\(message)"
        case .statementFailed(let message): "无法准备数据库操作：\(message)"
        case .bindingFailed(let message): "无法写入数据库参数：\(message)"
        case .executionFailed(let message): "本地数据库操作失败：\(message)"
        }
    }
}

/// Local source of truth for portfolio snapshots, price history and the user's trade ledger.
/// All calls currently happen on AppModel's main actor; SQLite is opened in full-mutex mode
/// so the storage layer remains safe when persistence moves to a background actor later.
final class InvestmentDatabase {
    let fileURL: URL

    private var connection: OpaquePointer?
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(fileURL: URL? = nil) throws {
        let resolvedURL = try fileURL ?? Self.defaultDatabaseURL()
        self.fileURL = resolvedURL

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(resolvedURL.path, &connection, flags, nil) == SQLITE_OK else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            if let connection { sqlite3_close(connection) }
            connection = nil
            throw DatabaseError.openFailed(message)
        }

        sqlite3_busy_timeout(connection, 3_000)
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try migrateIfNeeded()
    }

    deinit {
        if let connection { sqlite3_close(connection) }
    }

    func loadPortfolio() throws -> PortfolioSnapshot? {
        guard let state = try loadPortfolioState() else { return nil }
        let holdings = try loadHoldings()
        return PortfolioSnapshot(
            holdings: holdings,
            cash: state.cash,
            currency: state.currency,
            updatedAt: state.updatedAt
        )
    }

    func savePortfolio(_ portfolio: PortfolioSnapshot) throws {
        try inTransaction {
            try savePortfolioInternal(portfolio)
        }
    }

    func loadWorkspaceContent() throws -> WorkspaceContent? {
        try withStatement(
            "SELECT payload_json FROM workspace_content WHERE id = 1;"
        ) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decode(WorkspaceContent.self, from: text(statement, 0))
        }
    }

    func saveWorkspaceContent(_ content: WorkspaceContent) throws {
        let sql = """
        INSERT INTO workspace_content(id, payload_json, updated_at)
        VALUES(1, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            payload_json = excluded.payload_json,
            updated_at = excluded.updated_at;
        """
        try withStatement(sql) { statement in
            try bind(try encode(content), at: 1, in: statement)
            try bind(Date.now.timeIntervalSince1970, at: 2, in: statement)
            try stepDone(statement)
        }
    }

    func loadTrades(limit: Int = 100) throws -> [RecordedTrade] {
        let sql = """
        SELECT id, holding_id, symbol, name, asset_type, side, quantity, price,
               fees, currency, exchange_rate_to_base, traded_at, note, created_at
        FROM recorded_trades
        ORDER BY traded_at DESC, created_at DESC
        LIMIT ?;
        """

        return try withStatement(sql) { statement in
            try bind(Int64(limit), at: 1, in: statement)
            var trades: [RecordedTrade] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                trades.append(
                    RecordedTrade(
                        id: text(statement, 0),
                        holdingID: optionalText(statement, 1),
                        symbol: text(statement, 2),
                        name: text(statement, 3),
                        assetType: AssetType(rawValue: text(statement, 4)) ?? .other,
                        side: TradeSide(rawValue: text(statement, 5)) ?? .buy,
                        quantity: sqlite3_column_double(statement, 6),
                        price: sqlite3_column_double(statement, 7),
                        fees: sqlite3_column_double(statement, 8),
                        currency: text(statement, 9),
                        exchangeRateToBase: sqlite3_column_double(statement, 10),
                        tradedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
                        note: text(statement, 12),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 13))
                    )
                )
            }
            return trades
        }
    }

    func recordTrade(_ trade: RecordedTrade, updatedPortfolio: PortfolioSnapshot?) throws {
        try inTransaction {
            try insertTradeInternal(trade)
            if let updatedPortfolio {
                try savePortfolioInternal(updatedPortfolio)
            }
        }
    }

    func bootstrapLearning(
        units: [LearningUnit],
        settings: LearningSettings,
        methodology: [MethodologyNote]
    ) throws {
        try inTransaction {
            // Refresh bundled lessons on app upgrades while preserving progress and
            // a Codex-generated lesson that intentionally owns the same ID.
            for unit in units { try upsertBundledLearningUnitInternal(unit) }

            if try rowCount(in: "learning_settings") == 0 {
                try saveLearningSettingsInternal(settings)
            }

            if try rowCount(in: "methodology_notes") == 0 {
                for note in methodology { try saveMethodologyNoteInternal(note) }
            }
        }
    }

    func loadLearningState() throws -> LearningState {
        LearningState(
            units: try loadLearningUnits(),
            progress: try loadLessonProgress(),
            methodology: try loadMethodologyNotes(),
            notes: try loadLearningNotes(),
            settings: try loadLearningSettings() ?? .default
        )
    }

    func saveLearningUnit(_ unit: LearningUnit) throws {
        try upsertLearningUnitInternal(unit)
    }

    func saveLessonProgress(_ progress: LessonProgress) throws {
        let sql = """
        INSERT INTO lesson_progress(
            unit_id, status, quiz_score, confidence, completed_at, updated_at
        ) VALUES(?, ?, ?, ?, ?, ?)
        ON CONFLICT(unit_id) DO UPDATE SET
            status = excluded.status,
            quiz_score = excluded.quiz_score,
            confidence = excluded.confidence,
            completed_at = excluded.completed_at,
            updated_at = excluded.updated_at;
        """
        try withStatement(sql) { statement in
            try bind(progress.unitID, at: 1, in: statement)
            try bind(progress.status.rawValue, at: 2, in: statement)
            try bindOptional(progress.quizScore, at: 3, in: statement)
            try bind(Int64(progress.confidence), at: 4, in: statement)
            try bindOptional(progress.completedAt?.timeIntervalSince1970, at: 5, in: statement)
            try bind(progress.updatedAt.timeIntervalSince1970, at: 6, in: statement)
            try stepDone(statement)
        }
    }

    func recordQuizAttempt(_ attempt: QuizAttempt, progress: LessonProgress) throws {
        try inTransaction {
            let sql = """
            INSERT INTO quiz_attempts(id, unit_id, score, attempted_at)
            VALUES(?, ?, ?, ?);
            """
            try withStatement(sql) { statement in
                try bind(attempt.id, at: 1, in: statement)
                try bind(attempt.unitID, at: 2, in: statement)
                try bind(attempt.score, at: 3, in: statement)
                try bind(attempt.attemptedAt.timeIntervalSince1970, at: 4, in: statement)
                try stepDone(statement)
            }
            try saveLessonProgress(progress)
        }
    }

    func saveMethodologyNote(_ note: MethodologyNote) throws {
        try saveMethodologyNoteInternal(note)
    }

    func saveLearningNote(_ note: LearningNote) throws {
        let sql = """
        INSERT INTO learning_notes(id, unit_id, body, created_at, updated_at)
        VALUES(?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            unit_id = excluded.unit_id,
            body = excluded.body,
            updated_at = excluded.updated_at;
        """
        try withStatement(sql) { statement in
            try bind(note.id, at: 1, in: statement)
            try bindOptional(note.unitID, at: 2, in: statement)
            try bind(note.body, at: 3, in: statement)
            try bind(note.createdAt.timeIntervalSince1970, at: 4, in: statement)
            try bind(note.updatedAt.timeIntervalSince1970, at: 5, in: statement)
            try stepDone(statement)
        }
    }

    func deleteLearningNote(id: String) throws {
        try withStatement("DELETE FROM learning_notes WHERE id = ?;") { statement in
            try bind(id, at: 1, in: statement)
            try stepDone(statement)
        }
    }

    func saveLearningSettings(_ settings: LearningSettings) throws {
        try saveLearningSettingsInternal(settings)
    }

    func recordLearningSync(source: String, importedCount: Int, message: String) throws {
        let sql = """
        INSERT INTO learning_sync_runs(id, source, imported_count, message, imported_at)
        VALUES(?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(UUID().uuidString, at: 1, in: statement)
            try bind(source, at: 2, in: statement)
            try bind(Int64(importedCount), at: 3, in: statement)
            try bind(message, at: 4, in: statement)
            try bind(Date.now.timeIntervalSince1970, at: 5, in: statement)
            try stepDone(statement)
        }
    }

    func statistics() throws -> DatabaseStatistics {
        DatabaseStatistics(
            holdingCount: try rowCount(in: "holdings"),
            pricePointCount: try rowCount(in: "price_points"),
            tradeCount: try rowCount(in: "recorded_trades"),
            cashSnapshotCount: try rowCount(in: "cash_snapshots"),
            learningUnitCount: try rowCount(in: "learning_units"),
            completedLessonCount: try scalarInt(
                "SELECT COUNT(*) FROM lesson_progress WHERE status = '已完成';"
            ),
            learningNoteCount: try rowCount(in: "learning_notes")
        )
    }

    private static func defaultDatabaseURL() throws -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let directory = baseURL.appendingPathComponent("AIInvest", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory.appendingPathComponent("AIInvest.sqlite")
    }

    private func migrateIfNeeded() throws {
        var version = try scalarInt("PRAGMA user_version;")

        if version < 1 {
            try inTransaction {
                try execute("""
            CREATE TABLE IF NOT EXISTS portfolio_state (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                cash_amount REAL NOT NULL,
                base_currency TEXT NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS holdings (
                id TEXT PRIMARY KEY,
                symbol TEXT NOT NULL,
                name TEXT NOT NULL,
                asset_type TEXT NOT NULL,
                sector TEXT NOT NULL,
                currency TEXT NOT NULL,
                quantity REAL NOT NULL,
                available_quantity REAL NOT NULL,
                average_cost REAL NOT NULL,
                last_price REAL NOT NULL,
                daily_change_percent REAL NOT NULL,
                exchange_rate_to_base REAL NOT NULL,
                source TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS price_points (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                holding_id TEXT NOT NULL,
                symbol TEXT NOT NULL,
                price REAL NOT NULL,
                currency TEXT NOT NULL,
                exchange_rate_to_base REAL NOT NULL,
                recorded_at REAL NOT NULL,
                source TEXT NOT NULL,
                UNIQUE(holding_id, recorded_at)
            );

            CREATE INDEX IF NOT EXISTS idx_price_points_holding_date
            ON price_points(holding_id, recorded_at DESC);

            CREATE TABLE IF NOT EXISTS cash_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                amount REAL NOT NULL,
                currency TEXT NOT NULL,
                recorded_at REAL NOT NULL,
                source TEXT NOT NULL,
                UNIQUE(amount, currency, recorded_at)
            );

            CREATE INDEX IF NOT EXISTS idx_cash_snapshots_date
            ON cash_snapshots(recorded_at DESC);

            CREATE TABLE IF NOT EXISTS recorded_trades (
                id TEXT PRIMARY KEY,
                holding_id TEXT,
                symbol TEXT NOT NULL,
                name TEXT NOT NULL,
                asset_type TEXT NOT NULL,
                side TEXT NOT NULL,
                quantity REAL NOT NULL CHECK(quantity > 0),
                price REAL NOT NULL CHECK(price >= 0),
                fees REAL NOT NULL CHECK(fees >= 0),
                currency TEXT NOT NULL,
                exchange_rate_to_base REAL NOT NULL CHECK(exchange_rate_to_base > 0),
                traded_at REAL NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_recorded_trades_date
            ON recorded_trades(traded_at DESC);

            PRAGMA user_version = 1;
            """)
            }
            version = 1
        }

        if version < 2 {
            try inTransaction {
                try execute("""
                CREATE TABLE IF NOT EXISTS learning_units (
                    id TEXT PRIMARY KEY,
                    week_number INTEGER NOT NULL CHECK(week_number BETWEEN 1 AND 4),
                    day_number INTEGER NOT NULL CHECK(day_number BETWEEN 1 AND 28),
                    track TEXT NOT NULL,
                    title TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    source TEXT NOT NULL,
                    generated_at REAL,
                    updated_at REAL NOT NULL
                );

                CREATE UNIQUE INDEX IF NOT EXISTS idx_learning_units_day
                ON learning_units(day_number);

                CREATE TABLE IF NOT EXISTS lesson_progress (
                    unit_id TEXT PRIMARY KEY,
                    status TEXT NOT NULL,
                    quiz_score REAL,
                    confidence INTEGER NOT NULL DEFAULT 0 CHECK(confidence BETWEEN 0 AND 5),
                    completed_at REAL,
                    updated_at REAL NOT NULL,
                    FOREIGN KEY(unit_id) REFERENCES learning_units(id) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS quiz_attempts (
                    id TEXT PRIMARY KEY,
                    unit_id TEXT NOT NULL,
                    score REAL NOT NULL CHECK(score BETWEEN 0 AND 100),
                    attempted_at REAL NOT NULL,
                    FOREIGN KEY(unit_id) REFERENCES learning_units(id) ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS idx_quiz_attempts_unit_date
                ON quiz_attempts(unit_id, attempted_at DESC);

                CREATE TABLE IF NOT EXISTS methodology_notes (
                    section TEXT PRIMARY KEY,
                    content TEXT NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS learning_notes (
                    id TEXT PRIMARY KEY,
                    unit_id TEXT,
                    body TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    FOREIGN KEY(unit_id) REFERENCES learning_units(id) ON DELETE SET NULL
                );

                CREATE INDEX IF NOT EXISTS idx_learning_notes_date
                ON learning_notes(updated_at DESC);

                CREATE TABLE IF NOT EXISTS learning_settings (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    course_start_date REAL NOT NULL,
                    daily_minutes INTEGER NOT NULL CHECK(daily_minutes > 0),
                    generation_hour INTEGER NOT NULL CHECK(generation_hour BETWEEN 0 AND 23),
                    generation_minute INTEGER NOT NULL CHECK(generation_minute BETWEEN 0 AND 59),
                    workspace_path TEXT,
                    holdings_context_enabled INTEGER NOT NULL DEFAULT 0,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS learning_sync_runs (
                    id TEXT PRIMARY KEY,
                    source TEXT NOT NULL,
                    imported_count INTEGER NOT NULL,
                    message TEXT NOT NULL,
                    imported_at REAL NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_learning_sync_runs_date
                ON learning_sync_runs(imported_at DESC);

                PRAGMA user_version = 2;
                """)
            }
        }

        if version < 3 {
            try inTransaction {
                try execute("""
                CREATE TABLE IF NOT EXISTS workspace_content (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    payload_json TEXT NOT NULL,
                    updated_at REAL NOT NULL
                );

                PRAGMA user_version = 3;
                """)
            }
        }
    }

    private func loadLearningUnits() throws -> [LearningUnit] {
        let sql = """
        SELECT payload_json
        FROM learning_units
        ORDER BY day_number;
        """
        return try withStatement(sql) { statement in
            var units: [LearningUnit] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                units.append(try decode(LearningUnit.self, from: text(statement, 0)))
            }
            return units
        }
    }

    private func upsertLearningUnitInternal(_ unit: LearningUnit) throws {
        let sql = """
        INSERT INTO learning_units(
            id, week_number, day_number, track, title, payload_json,
            source, generated_at, updated_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            week_number = excluded.week_number,
            day_number = excluded.day_number,
            track = excluded.track,
            title = excluded.title,
            payload_json = excluded.payload_json,
            source = excluded.source,
            generated_at = excluded.generated_at,
            updated_at = excluded.updated_at;
        """
        try withStatement(sql) { statement in
            try bind(unit.id, at: 1, in: statement)
            try bind(Int64(unit.week), at: 2, in: statement)
            try bind(Int64(unit.day), at: 3, in: statement)
            try bind(unit.track.rawValue, at: 4, in: statement)
            try bind(unit.title, at: 5, in: statement)
            try bind(try encode(unit), at: 6, in: statement)
            try bind(unit.source.rawValue, at: 7, in: statement)
            try bindOptional(unit.generatedAt?.timeIntervalSince1970, at: 8, in: statement)
            try bind(Date.now.timeIntervalSince1970, at: 9, in: statement)
            try stepDone(statement)
        }
    }

    private func upsertBundledLearningUnitInternal(_ unit: LearningUnit) throws {
        let sql = """
        INSERT INTO learning_units(
            id, week_number, day_number, track, title, payload_json,
            source, generated_at, updated_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            week_number = excluded.week_number,
            day_number = excluded.day_number,
            track = excluded.track,
            title = excluded.title,
            payload_json = excluded.payload_json,
            source = excluded.source,
            generated_at = excluded.generated_at,
            updated_at = excluded.updated_at
        WHERE learning_units.source = ?;
        """
        try withStatement(sql) { statement in
            try bind(unit.id, at: 1, in: statement)
            try bind(Int64(unit.week), at: 2, in: statement)
            try bind(Int64(unit.day), at: 3, in: statement)
            try bind(unit.track.rawValue, at: 4, in: statement)
            try bind(unit.title, at: 5, in: statement)
            try bind(try encode(unit), at: 6, in: statement)
            try bind(unit.source.rawValue, at: 7, in: statement)
            try bindOptional(unit.generatedAt?.timeIntervalSince1970, at: 8, in: statement)
            try bind(Date.now.timeIntervalSince1970, at: 9, in: statement)
            try bind(LessonSource.builtIn.rawValue, at: 10, in: statement)
            try stepDone(statement)
        }
    }

    private func loadLessonProgress() throws -> [String: LessonProgress] {
        let sql = """
        SELECT unit_id, status, quiz_score, confidence, completed_at, updated_at
        FROM lesson_progress;
        """
        return try withStatement(sql) { statement in
            var progress: [String: LessonProgress] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                let unitID = text(statement, 0)
                progress[unitID] = LessonProgress(
                    unitID: unitID,
                    status: LessonProgressStatus(rawValue: text(statement, 1)) ?? .notStarted,
                    quizScore: optionalDouble(statement, 2),
                    confidence: Int(sqlite3_column_int64(statement, 3)),
                    completedAt: optionalDouble(statement, 4).map(Date.init(timeIntervalSince1970:)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                )
            }
            return progress
        }
    }

    private func loadMethodologyNotes() throws -> [MethodologyNote] {
        let sql = """
        SELECT section, content, updated_at
        FROM methodology_notes
        ORDER BY rowid;
        """
        return try withStatement(sql) { statement in
            var notes: [MethodologyNote] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let section = MethodologySection(rawValue: text(statement, 0)) else { continue }
                notes.append(
                    MethodologyNote(
                        section: section,
                        content: text(statement, 1),
                        updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                    )
                )
            }
            return notes
        }
    }

    private func saveMethodologyNoteInternal(_ note: MethodologyNote) throws {
        let sql = """
        INSERT INTO methodology_notes(section, content, updated_at)
        VALUES(?, ?, ?)
        ON CONFLICT(section) DO UPDATE SET
            content = excluded.content,
            updated_at = excluded.updated_at;
        """
        try withStatement(sql) { statement in
            try bind(note.section.rawValue, at: 1, in: statement)
            try bind(note.content, at: 2, in: statement)
            try bind(note.updatedAt.timeIntervalSince1970, at: 3, in: statement)
            try stepDone(statement)
        }
    }

    private func loadLearningNotes() throws -> [LearningNote] {
        let sql = """
        SELECT id, unit_id, body, created_at, updated_at
        FROM learning_notes
        ORDER BY updated_at DESC;
        """
        return try withStatement(sql) { statement in
            var notes: [LearningNote] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                notes.append(
                    LearningNote(
                        id: text(statement, 0),
                        unitID: optionalText(statement, 1),
                        body: text(statement, 2),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                        updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                    )
                )
            }
            return notes
        }
    }

    private func loadLearningSettings() throws -> LearningSettings? {
        let sql = """
        SELECT course_start_date, daily_minutes, generation_hour, generation_minute,
               workspace_path, holdings_context_enabled, updated_at
        FROM learning_settings
        WHERE id = 1;
        """
        return try withStatement(sql) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return LearningSettings(
                courseStartDate: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                dailyMinutes: Int(sqlite3_column_int64(statement, 1)),
                generationHour: Int(sqlite3_column_int64(statement, 2)),
                generationMinute: Int(sqlite3_column_int64(statement, 3)),
                workspacePath: optionalText(statement, 4),
                holdingsContextEnabled: sqlite3_column_int64(statement, 5) == 1,
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
            )
        }
    }

    private func saveLearningSettingsInternal(_ settings: LearningSettings) throws {
        let sql = """
        INSERT INTO learning_settings(
            id, course_start_date, daily_minutes, generation_hour, generation_minute,
            workspace_path, holdings_context_enabled, updated_at
        ) VALUES(1, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            course_start_date = excluded.course_start_date,
            daily_minutes = excluded.daily_minutes,
            generation_hour = excluded.generation_hour,
            generation_minute = excluded.generation_minute,
            workspace_path = excluded.workspace_path,
            holdings_context_enabled = excluded.holdings_context_enabled,
            updated_at = excluded.updated_at;
        """
        try withStatement(sql) { statement in
            try bind(settings.courseStartDate.timeIntervalSince1970, at: 1, in: statement)
            try bind(Int64(settings.dailyMinutes), at: 2, in: statement)
            try bind(Int64(settings.generationHour), at: 3, in: statement)
            try bind(Int64(settings.generationMinute), at: 4, in: statement)
            try bindOptional(settings.workspacePath, at: 5, in: statement)
            try bind(Int64(settings.holdingsContextEnabled ? 1 : 0), at: 6, in: statement)
            try bind(settings.updatedAt.timeIntervalSince1970, at: 7, in: statement)
            try stepDone(statement)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        } catch {
            throw DatabaseError.executionFailed("本地内容编码失败：\(error.localizedDescription)")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode(type, from: Data(value.utf8))
        } catch {
            throw DatabaseError.executionFailed("本地内容解码失败：\(error.localizedDescription)")
        }
    }

    private func loadPortfolioState() throws -> (cash: Double, currency: String, updatedAt: Date)? {
        try withStatement(
            "SELECT cash_amount, base_currency, updated_at FROM portfolio_state WHERE id = 1;"
        ) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return (
                sqlite3_column_double(statement, 0),
                text(statement, 1),
                Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            )
        }
    }

    private func loadHoldings() throws -> [Holding] {
        let sql = """
        SELECT id, symbol, name, asset_type, sector, currency, quantity,
               available_quantity, average_cost, last_price, daily_change_percent,
               exchange_rate_to_base, source, note, updated_at
        FROM holdings
        ORDER BY CASE source WHEN '长桥同步' THEN 0 ELSE 1 END, name;
        """

        return try withStatement(sql) { statement in
            var holdings: [Holding] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                holdings.append(
                    Holding(
                        id: text(statement, 0),
                        symbol: text(statement, 1),
                        name: text(statement, 2),
                        assetType: AssetType(rawValue: text(statement, 3)) ?? .other,
                        sector: text(statement, 4),
                        currency: text(statement, 5),
                        shares: sqlite3_column_double(statement, 6),
                        availableShares: sqlite3_column_double(statement, 7),
                        averageCost: sqlite3_column_double(statement, 8),
                        lastPrice: sqlite3_column_double(statement, 9),
                        dailyChangePercent: sqlite3_column_double(statement, 10),
                        exchangeRateToBase: sqlite3_column_double(statement, 11),
                        source: HoldingSource(rawValue: text(statement, 12)) ?? .manual,
                        note: text(statement, 13),
                        updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 14))
                    )
                )
            }
            return holdings
        }
    }

    private func savePortfolioInternal(_ portfolio: PortfolioSnapshot) throws {
        let stateSQL = """
        INSERT INTO portfolio_state(id, cash_amount, base_currency, updated_at)
        VALUES(1, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            cash_amount = excluded.cash_amount,
            base_currency = excluded.base_currency,
            updated_at = excluded.updated_at;
        """
        try withStatement(stateSQL) { statement in
            try bind(portfolio.cash, at: 1, in: statement)
            try bind(portfolio.currency, at: 2, in: statement)
            try bind(portfolio.updatedAt.timeIntervalSince1970, at: 3, in: statement)
            try stepDone(statement)
        }

        let existingIDs = Set(try loadHoldingIDs())
        let currentIDs = Set(portfolio.holdings.map(\.id))
        for removedID in existingIDs.subtracting(currentIDs) {
            try withStatement("DELETE FROM holdings WHERE id = ?;") { statement in
                try bind(removedID, at: 1, in: statement)
                try stepDone(statement)
            }
        }

        for holding in portfolio.holdings {
            try upsertHolding(holding)
            try insertPricePoint(holding)
        }

        let cashSource = portfolio.holdings.contains { $0.source == .longbridge }
            ? HoldingSource.longbridge.rawValue
            : HoldingSource.manual.rawValue
        try withStatement(
            "INSERT OR IGNORE INTO cash_snapshots(amount, currency, recorded_at, source) VALUES(?, ?, ?, ?);"
        ) { statement in
            try bind(portfolio.cash, at: 1, in: statement)
            try bind(portfolio.currency, at: 2, in: statement)
            try bind(portfolio.updatedAt.timeIntervalSince1970, at: 3, in: statement)
            try bind(cashSource, at: 4, in: statement)
            try stepDone(statement)
        }
    }

    private func upsertHolding(_ holding: Holding) throws {
        let sql = """
        INSERT INTO holdings(
            id, symbol, name, asset_type, sector, currency, quantity,
            available_quantity, average_cost, last_price, daily_change_percent,
            exchange_rate_to_base, source, note, updated_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            symbol = excluded.symbol,
            name = excluded.name,
            asset_type = excluded.asset_type,
            sector = excluded.sector,
            currency = excluded.currency,
            quantity = excluded.quantity,
            available_quantity = excluded.available_quantity,
            average_cost = excluded.average_cost,
            last_price = excluded.last_price,
            daily_change_percent = excluded.daily_change_percent,
            exchange_rate_to_base = excluded.exchange_rate_to_base,
            source = excluded.source,
            note = excluded.note,
            updated_at = excluded.updated_at;
        """

        try withStatement(sql) { statement in
            try bind(holding.id, at: 1, in: statement)
            try bind(holding.symbol, at: 2, in: statement)
            try bind(holding.name, at: 3, in: statement)
            try bind(holding.assetType.rawValue, at: 4, in: statement)
            try bind(holding.sector, at: 5, in: statement)
            try bind(holding.currency, at: 6, in: statement)
            try bind(holding.shares, at: 7, in: statement)
            try bind(holding.availableShares, at: 8, in: statement)
            try bind(holding.averageCost, at: 9, in: statement)
            try bind(holding.lastPrice, at: 10, in: statement)
            try bind(holding.dailyChangePercent, at: 11, in: statement)
            try bind(holding.exchangeRateToBase, at: 12, in: statement)
            try bind(holding.source.rawValue, at: 13, in: statement)
            try bind(holding.note, at: 14, in: statement)
            try bind(holding.updatedAt.timeIntervalSince1970, at: 15, in: statement)
            try stepDone(statement)
        }
    }

    private func insertPricePoint(_ holding: Holding) throws {
        guard holding.lastPrice >= 0, holding.exchangeRateToBase > 0 else { return }
        let sql = """
        INSERT OR IGNORE INTO price_points(
            holding_id, symbol, price, currency, exchange_rate_to_base, recorded_at, source
        ) VALUES(?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(holding.id, at: 1, in: statement)
            try bind(holding.symbol, at: 2, in: statement)
            try bind(holding.lastPrice, at: 3, in: statement)
            try bind(holding.currency, at: 4, in: statement)
            try bind(holding.exchangeRateToBase, at: 5, in: statement)
            try bind(holding.updatedAt.timeIntervalSince1970, at: 6, in: statement)
            try bind(holding.source.rawValue, at: 7, in: statement)
            try stepDone(statement)
        }
    }

    private func insertTradeInternal(_ trade: RecordedTrade) throws {
        let sql = """
        INSERT INTO recorded_trades(
            id, holding_id, symbol, name, asset_type, side, quantity, price,
            fees, currency, exchange_rate_to_base, traded_at, note, created_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(trade.id, at: 1, in: statement)
            try bindOptional(trade.holdingID, at: 2, in: statement)
            try bind(trade.symbol, at: 3, in: statement)
            try bind(trade.name, at: 4, in: statement)
            try bind(trade.assetType.rawValue, at: 5, in: statement)
            try bind(trade.side.rawValue, at: 6, in: statement)
            try bind(trade.quantity, at: 7, in: statement)
            try bind(trade.price, at: 8, in: statement)
            try bind(trade.fees, at: 9, in: statement)
            try bind(trade.currency, at: 10, in: statement)
            try bind(trade.exchangeRateToBase, at: 11, in: statement)
            try bind(trade.tradedAt.timeIntervalSince1970, at: 12, in: statement)
            try bind(trade.note, at: 13, in: statement)
            try bind(trade.createdAt.timeIntervalSince1970, at: 14, in: statement)
            try stepDone(statement)
        }
    }

    private func loadHoldingIDs() throws -> [String] {
        try withStatement("SELECT id FROM holdings;") { statement in
            var ids: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW { ids.append(text(statement, 0)) }
            return ids
        }
    }

    private func rowCount(in table: String) throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM \(table);")
    }

    private func scalarInt(_ sql: String) throws -> Int {
        try withStatement(sql) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private func inTransaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try work()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard let connection else { throw DatabaseError.openFailed("连接已关闭") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(connection, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(connection))
            sqlite3_free(errorMessage)
            throw DatabaseError.executionFailed(message)
        }
    }

    private func withStatement<T>(_ sql: String, body: (OpaquePointer) throws -> T) throws -> T {
        guard let connection else { throw DatabaseError.openFailed("连接已关闭") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw DatabaseError.statementFailed(String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            throw DatabaseError.executionFailed(message)
        }
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, transientDestructor) == SQLITE_OK else {
            throw DatabaseError.bindingFailed("文本参数 \(index)")
        }
    }

    private func bindOptional(_ value: String?, at index: Int32, in statement: OpaquePointer) throws {
        if let value {
            try bind(value, at: index, in: statement)
        } else if sqlite3_bind_null(statement, index) != SQLITE_OK {
            throw DatabaseError.bindingFailed("空参数 \(index)")
        }
    }

    private func bind(_ value: Double, at index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw DatabaseError.bindingFailed("数值参数 \(index)")
        }
    }

    private func bindOptional(_ value: Double?, at index: Int32, in statement: OpaquePointer) throws {
        if let value {
            try bind(value, at: index, in: statement)
        } else if sqlite3_bind_null(statement, index) != SQLITE_OK {
            throw DatabaseError.bindingFailed("空数值参数 \(index)")
        }
    }

    private func bind(_ value: Int64, at index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
            throw DatabaseError.bindingFailed("整数参数 \(index)")
        }
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func optionalText(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return text(statement, column)
    }

    private func optionalDouble(_ statement: OpaquePointer, _ column: Int32) -> Double? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, column)
    }
}
