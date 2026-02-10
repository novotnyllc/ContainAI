namespace ContainAI.Cli.Host;

internal sealed partial class ContainAiDockerProxyService
{
    private string ResolveContextName()
    {
        var contextName = environment.GetEnvironmentVariable("CONTAINAI_DOCKER_CONTEXT");
        if (string.IsNullOrWhiteSpace(contextName))
        {
            contextName = options.DefaultContext;
        }

        return contextName;
    }
}
