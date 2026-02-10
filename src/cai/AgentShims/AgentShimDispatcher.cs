namespace ContainAI.Cli.Host.AgentShims;

internal sealed class AgentShimDispatcher : IAgentShimDispatcher
{
    private readonly IAgentShimDefinitionResolver definitionResolver;
    private readonly IAgentShimBinaryResolver binaryResolver;
    private readonly IAgentShimCommandLauncher commandLauncher;
    private readonly TextWriter standardError;

    public AgentShimDispatcher(
        IAgentShimDefinitionResolver definitionResolver,
        IAgentShimBinaryResolver binaryResolver,
        IAgentShimCommandLauncher commandLauncher,
        TextWriter standardError)
    {
        this.definitionResolver = definitionResolver ?? throw new ArgumentNullException(nameof(definitionResolver));
        this.binaryResolver = binaryResolver ?? throw new ArgumentNullException(nameof(binaryResolver));
        this.commandLauncher = commandLauncher ?? throw new ArgumentNullException(nameof(commandLauncher));
        this.standardError = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public Task<int?> TryRunAsync(string invocationName, IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(invocationName) || string.Equals(invocationName, "cai", StringComparison.OrdinalIgnoreCase))
        {
            return Task.FromResult<int?>(null);
        }

        var definition = definitionResolver.Resolve(invocationName);
        if (definition is null)
        {
            return Task.FromResult<int?>(null);
        }

        return TryRunResolvedAsync(definition.Value, args, invocationName, cancellationToken);
    }

    private async Task<int?> TryRunResolvedAsync(
        ManifestAgentEntry definition,
        IReadOnlyList<string> args,
        string invocationName,
        CancellationToken cancellationToken)
    {
        var currentExecutable = binaryResolver.ResolveCurrentExecutablePath();
        var binaryPath = binaryResolver.ResolveBinaryPath(definition.Binary, binaryResolver.ResolveShimDirectories(), currentExecutable);
        if (binaryPath is null)
        {
            await standardError.WriteLineAsync(
                $"Agent '{invocationName}' is configured but binary '{definition.Binary}' was not found on PATH.")
                .ConfigureAwait(false);
            return 127;
        }

        var commandArgs = ComposeCommandArguments(definition.DefaultArgs, args);
        return await commandLauncher.ExecuteAsync(binaryPath, commandArgs, cancellationToken).ConfigureAwait(false);
    }

    private static List<string> ComposeCommandArguments(IReadOnlyList<string> defaultArgs, IReadOnlyList<string> args)
    {
        var commandArgs = new List<string>(defaultArgs.Count + args.Count);
        commandArgs.AddRange(defaultArgs);
        commandArgs.AddRange(args);
        return commandArgs;
    }
}
