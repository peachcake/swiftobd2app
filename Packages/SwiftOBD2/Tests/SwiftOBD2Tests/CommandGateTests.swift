//
//  CommandGateTests.swift
//  SwiftOBD2Tests
//

@testable import SwiftOBD2
import XCTest

final class CommandGateTests: XCTestCase {

    // MARK: - Allowed

    func testAdapterSetupCommandsUsedByLibraryAreAllowed() {
        let setup = ["ATZ", "ATD", "ATE0", "ATL0", "ATS0", "ATH1", "ATH0", "ATSP0", "ATSP6",
                     "ATDPN", "ATRV", "ATAT1", "ATSTFF", "AT SH 7E0", "ATSH7DF", "ATSH7E1"]
        for cmd in setup {
            XCTAssertTrue(CommandGate.isAllowed(cmd), cmd)
        }
        for p in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C"] {
            XCTAssertTrue(CommandGate.isAllowed("ATSP" + p), p)
        }
    }

    func testStandardReadsAreAllowed() {
        let reads = ["0100", "0105", "010C0D05", "010C0D050F1011", "0120", "03", "07", "0A",
                     "0601", "0902", "0904", "01 05", "010c"]
        for cmd in reads {
            XCTAssertTrue(CommandGate.isAllowed(cmd), cmd)
        }
    }

    func testToyotaTransmissionTempReadIsAllowed() {
        XCTAssertTrue(CommandGate.isAllowed("2182"))
        XCTAssertTrue(CommandGate.isAllowed("21 82"))
    }

    func testEveryLibraryCommandExceptClearIsAllowed() {
        // Guards against the gate silently breaking a built-in read.
        for command in OBDCommand.allCommands {
            let text = command.properties.command
            if text == "04" {
                XCTAssertFalse(CommandGate.isAllowed(text))
            } else {
                XCTAssertTrue(CommandGate.isAllowed(text), "\(command): \(text)")
            }
        }
    }

    func testNormalizesSpacesAndCase() throws {
        XCTAssertEqual(try CommandGate.check("at sh 7e0"), "ATSH7E0")
        XCTAssertEqual(try CommandGate.check("01 0c 0d"), "010C0D")
    }

    // MARK: - Blocked: writes and anything that changes the vehicle

    func testClearCodesIsBlocked() {
        XCTAssertFalse(CommandGate.isAllowed("04"))
        XCTAssertFalse(CommandGate.isAllowed("0400"))
        XCTAssertFalse(CommandGate.isAllowed("14FFFFFF")) // UDS clear DTC
    }

    func testUDSAndKWPWriteServicesAreBlocked() {
        let writes = [
            "08", "0801",            // OBD on-board control
            "1003", "1002",          // diagnostic session control
            "1101",                  // ECU reset
            "2701", "2702AABB",      // security access
            "2803",                  // communication control
            "2EF190AABB",            // write data by identifier
            "2F123403", "3001",      // I/O control
            "3101FF00",              // routine control
            "3400", "3500", "3601", "3700", // download / upload / transfer
            "3B9000", "3D00", "8502", // KWP write local id, write memory, DTC setting
            "3E00",                  // tester present (keeps sessions alive)
            "2183", "2101", "22F190", // reads not on the manufacturer allowlist
        ]
        for cmd in writes {
            XCTAssertFalse(CommandGate.isAllowed(cmd), cmd)
        }
    }

    // MARK: - Blocked: smuggling and malformed input

    func testLineBreaksCannotSmuggleASecondCommand() {
        for cmd in ["0100\r04", "0100\n04", "0100\r\n04", "ATZ\r04", "0100\u{0}04", "0100\t", "2182\r"] {
            XCTAssertFalse(CommandGate.isAllowed(cmd), CommandGate.printable(cmd))
        }
    }

    func testMalformedRequestsAreBlocked() {
        let bad = ["", " ", "0", "010", "0100 1", "01", "01010203040506070", "010102030405060708",
                   "GG", "01;04", "01-05", "0105é", "0601AA", "09", "0902AA", "03AA", "2182AA"]
        for cmd in bad {
            XCTAssertFalse(CommandGate.isAllowed(cmd), cmd)
        }
    }

    // MARK: - Blocked: adapter commands

    func testRiskyAdapterCommandsAreBlocked() {
        let risky = [
            "ATPP0CSV0F", "ATPP0CON", // write adapter EEPROM
            "ATBRD23",               // baud rate change
            "ATWM8110F13E", "ATSW00", // periodic wakeup frames on the bus
            "ATFI",                  // fast init
            "ATMA",                  // monitor all
            "ATSH7E2", "ATSH7FF", "ATSH18DA10F1", "ATSH", // headers not on the allowlist
            "ATSPD", "ATSP", "ATST1", // malformed settings
            "STPX H:7E0, D:1101", "STFF", "STI", // STN extended set
            "AT@3", "ATE1",
        ]
        for cmd in risky {
            XCTAssertFalse(CommandGate.isAllowed(cmd), cmd)
        }
    }

    func testBlockedErrorEscapesControlCharacters() {
        XCTAssertThrowsError(try CommandGate.check("0100\r04")) { error in
            XCTAssertEqual(error as? CommandGateError,
                           .blocked(command: "0100\\x0D04",
                                    reason: "control or non-ASCII characters are not allowed"))
        }
    }
}
