using System.Text.Json;

namespace ContainAI.Cli.Host.ConfigManifest;

internal interface IConfigReadOperation
{
    Task<int> ListAsync(string configPath, CancellationToken cancellationToken);

    Task<int> GetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken);
}

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

    private sealed class ConfigGetRequestResolver(ICaiConfigRuntime runtime)
    {
        public ConfigGetRequestResolution Resolve(ConfigCommandRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.Key))
            {
                return ConfigGetRequestResolution.Invalid("config get requires <key>");
            }

            var normalizedKey = runtime.NormalizeConfigKey(request.Key);
            var workspaceScope = runtime.ResolveWorkspaceScope(request, normalizedKey);
            if (workspaceScope.Error is not null)
            {
                return ConfigGetRequestResolution.Invalid(workspaceScope.Error);
            }

            return new ConfigGetRequestResolution(normalizedKey, workspaceScope.Workspace, request.Global);
        }
    }

    private sealed class ConfigValueReader(ICaiConfigRuntime runtime)
    {
        public Task<TomlProcessResult> ReadConfigJsonAsync(string configPath, CancellationToken cancellationToken) =>
            runtime.RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken);

        public Task<TomlProcessResult> ReadConfigKeyAsync(string configPath, string key, CancellationToken cancellationToken) =>
            runtime.RunTomlAsync(() => TomlCommandProcessor.GetKey(configPath, key), cancellationToken);

        public async Task<WorkspaceReadResult> ReadWorkspaceValueAsync(
            string configPath,
            string workspace,
            string requestKey,
            CancellationToken cancellationToken)
        {
            var workspaceResult = await runtime.RunTomlAsync(
                () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
                cancellationToken).ConfigureAwait(false);

            if (workspaceResult.ExitCode != 0)
            {
                return WorkspaceReadResult.ExecutionError;
            }

            using var wsJson = JsonDocument.Parse(workspaceResult.StandardOutput);
            if (wsJson.RootElement.ValueKind == JsonValueKind.Object &&
                wsJson.RootElement.TryGetProperty(requestKey, out var workspaceValue))
            {
                return WorkspaceReadResult.Found(workspaceValue.ToString());
            }

            return WorkspaceReadResult.Missing;
        }
    }

    private readonly record struct ConfigGetRequestResolution(
        string? NormalizedKey,
        string? Workspace,
        bool IsGlobal,
        string? Error = null)
    {
        public bool ShouldReadWorkspace => !IsGlobal && !string.IsNullOrWhiteSpace(Workspace);

        public static ConfigGetRequestResolution Invalid(string error) =>
            new(null, null, IsGlobal: false, Error: error);
    }

    private readonly record struct WorkspaceReadResult(WorkspaceReadState State, string? Value = null)
    {
        public static WorkspaceReadResult ExecutionError { get; } = new(WorkspaceReadState.ExecutionError);
        public static WorkspaceReadResult Missing { get; } = new(WorkspaceReadState.Missing);

        public static WorkspaceReadResult Found(string value) => new(WorkspaceReadState.Found, value);
    }

    private enum WorkspaceReadState
    {
        Found,
        Missing,
        ExecutionError
    }
}
