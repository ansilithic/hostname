import ArgumentParser
import CLICore
import Foundation

@main
struct Hostname: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hostname",
        abstract: "Show or change system hostname.",
        version: "1.0.0"
    )

    @Argument(help: "New hostname to set (omit to show current)")
    var newHostname: String?

    func run() {
        if let hostname = newHostname {
            changeHostname(to: hostname)
        } else {
            showCurrentHostnames()
        }
    }

    private func showCurrentHostnames() {
        print()
        print(styled("Current Hostnames", .bold, .cyan))
        print()

        let hostName = shell("scutil --get HostName 2>/dev/null")
        let localHostName = shell("scutil --get LocalHostName 2>/dev/null")
        let computerName = shell("scutil --get ComputerName 2>/dev/null")

        let labelWidth = 18

        func row(_ label: String, _ value: String, _ desc: String) {
            let paddedLabel = label.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
            print("  \(styled(paddedLabel, .gray))\(value.isEmpty ? styled("(not set)", .yellow) : value)")
            print("  \(styled("".padding(toLength: labelWidth, withPad: " ", startingAt: 0), .gray))\(styled(desc, .dim))")
        }

        row("HostName", hostName, "Terminal prompt, SSH")
        row("LocalHostName", localHostName.isEmpty ? "" : "\(localHostName).local", "Bonjour, AirDrop discovery")
        row("ComputerName", computerName, "Finder sidebar, file sharing")

        print()
    }

    private func changeHostname(to hostname: String) {
        let validPattern = "^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$"
        let regex = try? NSRegularExpression(pattern: validPattern)
        let range = NSRange(hostname.startIndex..., in: hostname)

        guard regex?.firstMatch(in: hostname, range: range) != nil else {
            Output.error("Invalid hostname '\(hostname)'")
            print("Hostname must:")
            print("  - Contain only letters, numbers, and hyphens")
            print("  - Start and end with a letter or number")
            print("  - Not contain spaces or special characters")
            CLIExitCode.error.exit()
        }

        showCurrentHostnames()

        print(styled("New hostname:", .yellow), hostname)
        print(styled("This will update all three settings.", .dim))
        print()

        guard let passPtr = getpass("Password: ") else {
            Output.error("Failed to read password")
            CLIExitCode.error.exit()
        }
        let password = String(cString: passPtr)

        // Validate password with a no-op before doing real work
        guard sudoExec("true", password: password) == 0 else {
            Output.error("Incorrect password")
            CLIExitCode.error.exit()
        }

        let commands = [
            "scutil --set HostName \(hostname)",
            "scutil --set LocalHostName \(hostname)",
            "scutil --set ComputerName \(hostname)",
            "dscacheutil -flushcache"
        ]

        for cmd in commands {
            if sudoExec(cmd, password: password) != 0 {
                Output.error("Failed to execute: \(cmd)")
                CLIExitCode.error.exit()
            }
        }

        Output.success("Hostname changed to: \(hostname)")
        print(styled("You may need to restart Terminal for the prompt to update.", .dim))
    }

    private func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = nil

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func sudoExec(_ command: String, password: String) -> Int32 {
        let task = Process()
        let stdinPipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-kS", "/bin/zsh", "-c", command]
        task.standardInput = stdinPipe
        task.standardOutput = nil
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return 1
        }

        stdinPipe.fileHandleForWriting.write(Data("\(password)\n".utf8))
        stdinPipe.fileHandleForWriting.closeFile()
        task.waitUntilExit()

        return task.terminationStatus
    }
}
