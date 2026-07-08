import PackagePlugin
import Foundation

@main
struct BuildNumberPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let outputDir = context.pluginWorkDirectory
        let outputFile = outputDir.appending("BuildInfo.swift")
        let counterFile = outputDir.appending("build-counter.txt")
        let script = context.package.directory.appending("Plugins", "BuildNumberPlugin", "generate-build-info.sh")

        return [
            .prebuildCommand(
                displayName: "Generating ELAP build number",
                executable: Path("/bin/sh"),
                arguments: [script.string, counterFile.string, outputFile.string],
                outputFilesDirectory: outputDir
            )
        ]
    }
}
