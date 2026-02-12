using CsToml.Error;

namespace ContainAI.Cli.Host;

internal interface ITomlCommandLoadService
{
    TomlLoadResult LoadToml(string filePath, int missingFileExitCode, string? missingFileMessage);
}
