namespace ContainAI.Cli.Host.Operations.Diagnostics.Setup;

internal readonly record struct CaiSetupPaths(string ContainAiDir, string SshDir, string SshKeyPath, string SocketPath);
