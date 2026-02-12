namespace ContainAI.Cli.Host.Sessions.Models;

internal readonly record struct ProcessResult(int ExitCode, string StandardOutput, string StandardError);
