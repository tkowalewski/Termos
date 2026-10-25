import Foundation

/// Runs the git command line tool.
enum Git {
    static let executable = URL(fileURLWithPath: "/usr/bin/git")

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Runs git in `directory` off the main thread and returns its standard output.
    @discardableResult
    static func output(
        _ arguments: [String], in directory: URL, input: Data? = nil, successCodes: Set<Int32> = [0]
    ) async throws -> Data {
        try await Task.detached {
            try run(arguments, in: directory, input: input, successCodes: successCodes)
        }.value
    }

    /// Runs git and returns its standard output. Exit codes outside `successCodes`
    /// throw with git's error message.
    @discardableResult
    static func run(
        _ arguments: [String], in directory: URL, input: Data? = nil, successCodes: Set<Int32> = [0]
    ) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw Failure(message: "Git is not installed. Install the Xcode Command Line Tools to review changes.")
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["-C", directory.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        // Reading the status must not take the index lock from git commands run in the terminal.
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        let output = Pipe()
        let errors = Pipe()
        let inputPipe = input.map { _ in Pipe() }
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = inputPipe ?? FileHandle.nullDevice

        try process.run()
        if let input, let inputPipe {
            inputPipe.fileHandleForWriting.write(input)
            try? inputPipe.fileHandleForWriting.close()
        }

        // Read both pipes at once, so a chatty stderr cannot block git while stdout is read.
        var errorData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errorData = errors.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        guard successCodes.contains(process.terminationStatus) else {
            let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: message.isEmpty ? "git \(arguments.first ?? "") failed." : message)
        }
        return data
    }
}
