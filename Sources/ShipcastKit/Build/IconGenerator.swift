import Foundation

public struct IconGenerator {
    public static func generateICNS(from sourcePNG: URL, to outputICNS: URL, shell: ShellRunner) throws {
        guard FileManager.default.fileExists(atPath: sourcePNG.path) else {
            throw ShipcastError.generic(
                "Icon not found: \(sourcePNG.path)",
                fix: "Place a 1024x1024 PNG at project root named icon.png"
            )
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let iconsetDir = tempDir.appendingPathComponent("AppIcon.iconset")
        try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

        // sips ladder from spec §Icon Generation
        let sizes: [(Int, String)] = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png"),
        ]

        for (size, filename) in sizes {
            let output = iconsetDir.appendingPathComponent(filename)
            let result = try shell.run(
                "/usr/bin/sips",
                args: ["-z", "\(size)", "\(size)", sourcePNG.path, "--out", output.path],
                env: nil
            )
            guard result.exitCode == 0 else {
                throw ShipcastError.generic(
                    "sips failed for \(filename):\n\(result.stderr)",
                    fix: "Ensure icon.png is a valid 1024x1024 PNG"
                )
            }
        }

        // iconutil compile
        let iconutilResult = try shell.run(
            "/usr/bin/iconutil",
            args: ["-c", "icns", iconsetDir.path, "-o", outputICNS.path],
            env: nil
        )
        guard iconutilResult.exitCode == 0 else {
            throw ShipcastError.generic(
                "iconutil failed:\n\(iconutilResult.stderr)",
                fix: "Check iconset structure in \(iconsetDir.path)"
            )
        }
    }
}
