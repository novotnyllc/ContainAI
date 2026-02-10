namespace ContainAI.Cli.Host;

internal static partial class CaiRuntimeDockerHelpers
{
    private static readonly string[] PreferredDockerContexts =
    [
        "containai-docker",
        "containai-secure",
        "docker-containai",
    ];
}
