import Foundation
import QuietTermCore
import Testing

@Test func passwordCredentialPassesNullTerminatedBytesAndDiscardsAfterUse() {
    var credential = SSHPasswordCredential("quiet-password")

    let byteCount = credential.byteCount
    #expect(byteCount == 14)

    let captured = credential.withNullTerminatedUTF8 { pointer in
        String(cString: pointer)
    }

    #expect(captured == "quiet-password")
    #expect(credential.byteCount == byteCount)

    credential.discard()

    #expect(credential.byteCount == 0)
    #expect(credential.isEmpty)
}

@Test func terminalInputEncodesRequiredKan16Keys() {
    #expect(TerminalInput.text("ls").bytes == [0x6c, 0x73])
    #expect(TerminalInput.enter.bytes == [0x0d])
    #expect(TerminalInput.backspace.bytes == [0x7f])
    #expect(TerminalInput.tab.bytes == [0x09])
    #expect(TerminalInput.arrowUp.bytes == [0x1b, 0x5b, 0x41])
    #expect(TerminalInput.arrowDown.bytes == [0x1b, 0x5b, 0x42])
    #expect(TerminalInput.arrowRight.bytes == [0x1b, 0x5b, 0x43])
    #expect(TerminalInput.arrowLeft.bytes == [0x1b, 0x5b, 0x44])
    #expect(TerminalInput.control("C").bytes == [0x03])
    #expect(TerminalInput.control("c").bytes == [0x03])
    #expect(TerminalInput.raw([0x1b]).bytes == [0x1b])
}
