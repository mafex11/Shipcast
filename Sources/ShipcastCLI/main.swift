import ArgumentParser

@main
struct Shipcast: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shipcast",
        abstract: "Mac app distribution pipeline",
        version: "0.1.0"
    )
}
