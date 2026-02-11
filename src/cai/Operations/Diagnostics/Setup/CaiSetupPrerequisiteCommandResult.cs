namespace ContainAI.Cli.Host.Operations.Diagnostics.Setup;

internal readonly record struct CaiSetupPrerequisiteCommandResult(int ExitCode, string StandardOutput, string StandardError);
