import Foundation

public enum TerminalRendererDefaults {
    public static let scrollbackLineLimit = 10_000
    public static let fallbackColumns = 80
    public static let fallbackRows = 24
}

public struct TerminalGridSize: Codable, Equatable, Sendable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }

    public init(
        viewportWidth: Double,
        viewportHeight: Double,
        cellWidth: Double,
        cellHeight: Double,
        horizontalInset: Double = 0,
        verticalInset: Double = 0
    ) {
        let usableWidth = max(0, viewportWidth - horizontalInset * 2)
        let usableHeight = max(0, viewportHeight - verticalInset * 2)
        let safeCellWidth = max(1, cellWidth)
        let safeCellHeight = max(1, cellHeight)

        self.init(
            columns: Int((usableWidth / safeCellWidth).rounded(.down)),
            rows: Int((usableHeight / safeCellHeight).rounded(.down))
        )
    }
}

public struct TerminalResizeEvent: Codable, Equatable, Sendable {
    public var gridSize: TerminalGridSize

    public init(gridSize: TerminalGridSize) {
        self.gridSize = gridSize
    }

    public init(columns: Int, rows: Int) {
        self.init(gridSize: TerminalGridSize(columns: columns, rows: rows))
    }
}

public struct TerminalOutputChunk: Codable, Equatable, Sendable {
    public var bytes: [UInt8]

    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    public init(text: String) {
        self.init(bytes: Array(text.utf8))
    }
}

public struct TerminalFixtureStream: Codable, Equatable, Sendable {
    public var chunks: [TerminalOutputChunk]

    public init(chunks: [TerminalOutputChunk]) {
        self.chunks = chunks
    }

    public var byteChunks: [[UInt8]] {
        chunks.map(\.bytes)
    }

    public var combinedBytes: [UInt8] {
        chunks.flatMap(\.bytes)
    }

    public static let kan21Demo = TerminalFixtureStream(chunks: [
        TerminalOutputChunk(text: "\u{001B}[2J\u{001B}[H"),
        TerminalOutputChunk(text: "\u{001B}[1;36mQuietTerm\u{001B}[0m renderer fixture\r\n"),
        TerminalOutputChunk(text: "UTF-8 sample: cafe\u{0301}, lambda \u{03BB}, rocket \u{1F680}\r\n"),
        TerminalOutputChunk(text: "\u{001B}[1;32mANSI green\u{001B}[0m "),
        TerminalOutputChunk(text: "\u{001B}[38;5;214m256-color orange\u{001B}[0m "),
        TerminalOutputChunk(text: "\u{001B}[38;2;120;200;255mtrue-color blue\u{001B}[0m\r\n"),
        TerminalOutputChunk(text: "Wrapping sample: this long line intentionally runs past a narrow phone-sized terminal viewport so the renderer has to wrap cleanly rather than clipping output.\r\n"),
        TerminalOutputChunk(text: "\u{001B}[5;1Hcursor movement landed here\u{001B}[K\r\n"),
        TerminalOutputChunk(text: "\u{001B}[?1049hAlternate screen fixture\r\nfull-screen command output placeholder\r\n\u{001B}[?1049l"),
        TerminalOutputChunk(text: "Returned from alternate screen.\r\n$ ")
    ])

    public static func scrollbackSmoke(lineCount: Int = TerminalRendererDefaults.scrollbackLineLimit) -> TerminalFixtureStream {
        let safeLineCount = max(0, lineCount)
        guard safeLineCount > 0 else {
            return TerminalFixtureStream(chunks: [])
        }

        return TerminalFixtureStream(
            chunks: (1...safeLineCount).map { lineNumber in
                TerminalOutputChunk(text: "scrollback smoke line \(lineNumber)\r\n")
            }
        )
    }
}
