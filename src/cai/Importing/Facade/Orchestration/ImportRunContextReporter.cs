namespace ContainAI.Cli.Host;

internal sealed class ImportRunContextReporter(TextWriter standardOutput, TextWriter standardError) : IImportRunContextReporter
{
    public async Task WriteContextAsync(ImportRunContext context, bool dryRun)
    {
        await standardOutput.WriteLineAsync($"Using data volume: {context.Volume}").ConfigureAwait(false);
        if (dryRun)
        {
            await standardOutput.WriteLineAsync($"Dry-run context: {ResolveDockerContextName()}").ConfigureAwait(false);
        }
    }

    public Task WriteRunContextErrorAsync(string error)
        => standardError.WriteLineAsync(error);

    public Task WriteManifestLoadErrorAsync(string error)
        => standardError.WriteLineAsync(error);

    private static string ResolveDockerContextName()
    {
        var explicitContext = Environment.GetEnvironmentVariable("DOCKER_CONTEXT");
        return !string.IsNullOrWhiteSpace(explicitContext)
            ? explicitContext
            : "default";
    }
}
