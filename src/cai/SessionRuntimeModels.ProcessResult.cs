namespace ContainAI.Cli.Host;

internal readonly record struct ProcessResult(int ExitCode, string StandardOutput, string StandardError);
