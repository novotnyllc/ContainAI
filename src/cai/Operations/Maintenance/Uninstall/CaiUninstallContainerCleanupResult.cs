namespace ContainAI.Cli.Host;

internal readonly record struct CaiUninstallContainerCleanupResult(int ExitCode, HashSet<string> VolumeNames);
