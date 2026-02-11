namespace ContainAI.Cli.Host.RuntimeSupport;

internal static partial class CaiRuntimeDockerHelpers
{
    private static readonly string[] PreferredDockerContexts =
    [
        "containai-docker",
        "containai-secure",
        "docker-containai",
    ];
}
