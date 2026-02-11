namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected readonly record struct ProcessResult(int ExitCode, string StandardOutput, string StandardError);

    protected readonly record struct ParsedImportOptions(
        string? SourcePath,
        string? ExplicitVolume,
        string? Workspace,
        string? ConfigPath,
        bool DryRun,
        bool NoExcludes,
        bool NoSecrets,
        bool Verbose,
        string? Error);

    protected readonly record struct EnvFilePathResolution(string? Path, string? Error);

    protected readonly record struct ParsedEnvFile(
        IReadOnlyDictionary<string, string> Values,
        IReadOnlyList<string> Warnings);

    protected readonly record struct ParsedConfigCommand(
        string Action,
        string? Key,
        string? Value,
        bool Global,
        string? Workspace,
        string? Error);
}
