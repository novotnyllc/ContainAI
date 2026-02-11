namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportOrchestrationOperations
{
    private static string ResolveDockerContextName()
    {
        var explicitContext = Environment.GetEnvironmentVariable("DOCKER_CONTEXT");
        if (!string.IsNullOrWhiteSpace(explicitContext))
        {
            return explicitContext;
        }

        return "default";
    }
}
