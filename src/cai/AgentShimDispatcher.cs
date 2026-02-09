namespace ContainAI.Cli.Host;

internal static partial class AgentShimDispatcher
{
    public static async Task<int?> TryRunAsync(string invocationName, IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(invocationName) || string.Equals(invocationName, "cai", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var definition = ResolveDefinition(invocationName);
        if (definition is null)
        {
            return null;
        }

        var currentExecutable = ResolveCurrentExecutablePath();
        var binaryPath = ResolveBinaryPath(definition.Value.Binary, ResolveShimDirectories(), currentExecutable);
        if (binaryPath is null)
        {
            await Console.Error.WriteLineAsync($"Agent '{invocationName}' is configured but binary '{definition.Value.Binary}' was not found on PATH.").ConfigureAwait(false);
            return 127;
        }

        var commandArgs = ComposeCommandArguments(definition.Value.DefaultArgs, args);
        return await ExecuteCommandAsync(binaryPath, commandArgs, cancellationToken).ConfigureAwait(false);
    }
}
