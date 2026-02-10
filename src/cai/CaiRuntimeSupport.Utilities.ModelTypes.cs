namespace ContainAI.Cli.Host;

internal readonly record struct RuntimeProcessResult(int ExitCode, string StandardOutput, string StandardError);

internal readonly record struct RuntimeEnvFilePathResolution(string? Path, string? Error);

internal readonly record struct RuntimeParsedEnvFile(
    IReadOnlyDictionary<string, string> Values,
    IReadOnlyList<string> Warnings);
