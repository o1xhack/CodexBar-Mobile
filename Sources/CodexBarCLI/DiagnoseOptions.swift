import CodexBarCore
import Commander
import Foundation

struct DiagnoseOptions: CommanderParsable {
    @OptionGroup
    var logging: CLILoggingOptions

    @Option(name: .long("provider"), help: ProviderHelp.optionHelp)
    var provider: String?

    @Option(name: .long("format"), help: "Output format: json")
    var format: String?

    @Flag(name: .long("redact"), help: "Explicitly redact sensitive values (always enabled for diagnose)")
    var redact: Bool = false

    @Option(name: .long("output"), help: "Write redacted JSON diagnostic export to a file")
    var output: String?

    @Flag(name: .long("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false
}
