using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal readonly record struct InstallCommandContext(
    InstallCommandOptions Options,
    string SourceExecutablePath,
    string InstallDir,
    string BinDir,
    string HomeDirectory);
