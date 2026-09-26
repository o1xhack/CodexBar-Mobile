import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeCLIPanelTransitionTests {
    @Test
    func `reused session dismisses panels before capturing identity and refreshing usage`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-panel-transition-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("fake-claude")
        let log = directory.appendingPathComponent("commands.log")
        let script = #"""
        #!/bin/bash
        /bin/stty raw -echo -icrnl
        printf 'launch\n' >> "$HOME/commands.log"
        panel=closed
        command=''
        while IFS= read -r -n 1 key; do
          case "$key" in
            $'\e')
              printf 'dismiss:%s\n' "$panel" >> "$HOME/commands.log"
              /bin/sleep 0.05
              panel=closed
              command=''
              printf 'prompt\r\n'
              ;;
            # read -n 1 reports a newline as an empty key.
            $'\r'|'')
              if [[ "$panel" == closed ]]; then
                printf '%s\n' "$command" >> "$HOME/commands.log"
                case "$command" in
                  /usage)
                    printf 'Current session\r\n9%% used\r\nDONE\r\n'
                    panel=usage
                    ;;
                  /status)
                    printf 'Email: fixture@example.com\r\nLogin method: Claude Max Account\r\nDONE\r\n'
                    panel=status
                    ;;
                esac
              fi
              command=''
              ;;
            *) command+="$key" ;;
          esac
        done
        """#
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let session = ClaudeCLISession(workingDirectory: directory)
        let environment = [
            "HOME": directory.path,
            "CLAUDE_CONFIG_DIR": directory.path,
            "CLAUDE_SECURESTORAGE_CONFIG_DIR": directory.path,
            "CODEXBAR_DISABLE_CLAUDE_WATCHDOG": "1",
        ]
        func capture(_ command: String) async throws -> String {
            try await session.capture(
                subcommand: command,
                binary: binary.path,
                accountScope: "synthetic-account",
                timeout: 3,
                environment: environment,
                idleTimeout: 0.5,
                stopOnSubstrings: ["DONE"],
                settleAfterStop: 0)
        }
        do {
            let usage = try await capture("/usage")
            let status = try await capture("/status")
            let snapshot = try ClaudeStatusProbe.parse(text: usage, statusText: status)
            #expect(snapshot.sessionPercentLeft == 91)
            #expect(snapshot.accountEmail == "fixture@example.com")
            #expect(snapshot.loginMethod == "Max")
            let refreshed = try await capture("/usage")
            #expect(try ClaudeStatusProbe.parse(text: refreshed).sessionPercentLeft == 91)
            await session.reset()
        } catch {
            print("Synthetic CLI commands:\n" + ((try? String(contentsOf: log, encoding: .utf8)) ?? "<none>"))
            await session.reset()
            throw error
        }
        #expect(try String(contentsOf: log, encoding: .utf8) == """
        launch
        /usage
        dismiss:usage
        /status
        dismiss:status
        /usage

        """)
    }
}
