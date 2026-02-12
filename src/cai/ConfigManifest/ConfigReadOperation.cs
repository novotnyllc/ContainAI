using ContainAI.Cli.Host.ConfigManifest.Reading;

namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ConfigReadOperation(
    TextWriter standardOutput,
    TextWriter standardError,
    ICaiConfigRuntime runtime) : IConfigReadOperation
{
    private readonly ConfigGetRequestResolver requestResolver = new(runtime);
    private readonly ConfigValueReader valueReader = new(runtime);

    public async Task<int> ListAsync(string configPath, CancellationToken cancellationToken)
    {
        var parseResult = await valueReader.ReadConfigJsonAsync(configPath, cancellationToken).ConfigureAwait(false);
        if (parseResult.ExitCode != 0)
        {
            await standardError.WriteLineAsync(parseResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        await standardOutput.WriteLineAsync(parseResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    public async Task<int> GetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken)
    {
        var resolvedRequest = requestResolver.Resolve(request);
        if (resolvedRequest.Error is not null)
        {
            await standardError.WriteLineAsync(resolvedRequest.Error).ConfigureAwait(false);
            return 1;
        }

        if (resolvedRequest.ShouldReadWorkspace)
        {
            var workspaceReadResult = await valueReader.ReadWorkspaceValueAsync(
                configPath,
                resolvedRequest.Workspace!,
                request.Key!,
                cancellationToken).ConfigureAwait(false);

            if (workspaceReadResult.State == WorkspaceReadState.ExecutionError)
            {
                return 1;
            }

            if (workspaceReadResult is { State: WorkspaceReadState.Found, Value: not null })
            {
                await standardOutput.WriteLineAsync(workspaceReadResult.Value).ConfigureAwait(false);
                return 0;
            }

            return 1;
        }

        var getResult = await valueReader.ReadConfigKeyAsync(
            configPath,
            resolvedRequest.NormalizedKey!,
            cancellationToken).ConfigureAwait(false);

        if (getResult.ExitCode != 0)
        {
            return 1;
        }

        await standardOutput.WriteLineAsync(getResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }
}
