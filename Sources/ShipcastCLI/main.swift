import ArgumentParser

struct Shipcast: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shipcast",
        abstract: "Mac app distribution pipeline",
        version: "0.1.0",
        subcommands: [Init.self, Build.self, Sign.self, PackageCommand.self]
    )
}

Shipcast.main()
