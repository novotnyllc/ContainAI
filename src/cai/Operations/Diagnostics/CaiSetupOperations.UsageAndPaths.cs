namespace ContainAI.Cli.Host;

internal sealed partial class CaiSetupOperations
{
    private const string SetupUsage = "Usage: cai setup [--dry-run] [--verbose] [--skip-templates]";
    private const string RuntimeSocketPath = "/var/run/containai-docker.sock";

    private Task WriteSetupUsageAsync() => stdout.WriteLineAsync(SetupUsage);

    private static SetupPaths ResolveSetupPaths()
    {
        var home = ResolveHomeDirectory();
        var containAiDir = Path.Combine(home, ".config", "containai");
        var sshDir = Path.Combine(home, ".ssh", "containai.d");
        var sshKeyPath = Path.Combine(containAiDir, "id_containai");

        return new SetupPaths(containAiDir, sshDir, sshKeyPath, RuntimeSocketPath);
    }

    private readonly record struct SetupPaths(string ContainAiDir, string SshDir, string SshKeyPath, string SocketPath);
}
