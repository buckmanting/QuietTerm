import Testing
@testable import QuietTermCore

@Test func terminalGridSizeCalculatesColumnsAndRowsFromViewport() {
    let gridSize = TerminalGridSize(
        viewportWidth: 401,
        viewportHeight: 803,
        cellWidth: 8,
        cellHeight: 17,
        horizontalInset: 1,
        verticalInset: 3
    )

    #expect(gridSize.columns == 49)
    #expect(gridSize.rows == 46)
}

@Test func terminalGridSizeNeverDropsBelowOneCell() {
    let gridSize = TerminalGridSize(
        viewportWidth: 0,
        viewportHeight: 0,
        cellWidth: 0,
        cellHeight: 0
    )

    #expect(gridSize == TerminalGridSize(columns: 1, rows: 1))
}

@Test func terminalResizeEventNormalizesGridSize() {
    let event = TerminalResizeEvent(columns: 0, rows: -12)

    #expect(event.gridSize == TerminalGridSize(columns: 1, rows: 1))
}

@Test func terminalFixtureStreamPreservesChunkOrdering() {
    let stream = TerminalFixtureStream(chunks: [
        TerminalOutputChunk(text: "first"),
        TerminalOutputChunk(bytes: [0x1B, 0x5B, 0x32, 0x4A]),
        TerminalOutputChunk(text: "last")
    ])

    #expect(stream.byteChunks == [
        Array("first".utf8),
        [0x1B, 0x5B, 0x32, 0x4A],
        Array("last".utf8)
    ])
    #expect(stream.combinedBytes == Array("first".utf8) + [0x1B, 0x5B, 0x32, 0x4A] + Array("last".utf8))
}

@Test func kan21FixtureIncludesTerminalRenderingCapabilities() {
    let text = String(decoding: TerminalFixtureStream.kan21Demo.combinedBytes, as: UTF8.self)

    #expect(text.contains("QuietTerm"))
    #expect(text.contains("\u{001B}[38;5;214m"))
    #expect(text.contains("\u{001B}[38;2;120;200;255m"))
    #expect(text.contains("\u{001B}[?1049h"))
    #expect(text.contains("\u{001B}[?1049l"))
}
