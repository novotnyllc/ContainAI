using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Operations.Diagnostics.Setup;

internal static class CaiSetupPathResolver
{
    private const string RuntimeSocketPath = "/var/run/containai-docker.sock";

    public static CaiSetupPaths ResolveSetupPaths()
    {
        var home = CaiRuntimeHomePathHelpers.ResolveHomeDirectory();
        var containAiDir = Path.Combine(home, ".config", "containai");
        var sshDir = Path.Combine(home, ".ssh", "containai.d");
        var sshKeyPath = Path.Combine(containAiDir, "id_containai");

        return new CaiSetupPaths(containAiDir, sshDir, sshKeyPath, RuntimeSocketPath);
    }
}
