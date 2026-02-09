using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportService : CaiRuntimeSupport
{
    public CaiImportService(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var parsed = new ParsedImportOptions(
            SourcePath: options.From,
            ExplicitVolume: options.DataVolume,
            Workspace: options.Workspace,
            ConfigPath: options.Config,
            DryRun: options.DryRun,
            NoExcludes: options.NoExcludes,
            NoSecrets: options.NoSecrets,
            Verbose: options.Verbose,
            Error: null);
        return RunImportCoreAsync(parsed, cancellationToken);
    }
}
