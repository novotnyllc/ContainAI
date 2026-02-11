using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host;

internal interface ICaiStopTargetResolver
{
    Task<ResolutionResult<IReadOnlyList<CaiStopTarget>>> ResolveAsync(
        string? containerName,
        bool stopAll,
        CancellationToken cancellationToken);
}

internal sealed class CaiStopTargetResolver : ICaiStopTargetResolver
{
    private static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    private readonly TextWriter stderr;

    public CaiStopTargetResolver(TextWriter standardError)
        => stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<ResolutionResult<IReadOnlyList<CaiStopTarget>>> ResolveAsync(
        string? containerName,
        bool stopAll,
        CancellationToken cancellationToken)
    {
        var targets = new List<CaiStopTarget>();
        if (!string.IsNullOrWhiteSpace(containerName))
        {
            var contexts = await CaiRuntimeDockerHelpers.FindContainerContextsAsync(containerName, cancellationToken).ConfigureAwait(false);
            if (!await TryResolveSingleTargetAsync(contexts, containerName).ConfigureAwait(false))
            {
                return ResolutionResult<IReadOnlyList<CaiStopTarget>>.ErrorResult("Unable to resolve stop target.");
            }

            targets.Add(new CaiStopTarget(contexts[0], containerName));
            return ResolutionResult<IReadOnlyList<CaiStopTarget>>.SuccessResult(targets);
        }

        if (stopAll)
        {
            foreach (var context in await CaiRuntimeDockerHelpers.GetAvailableContextsAsync(cancellationToken).ConfigureAwait(false))
            {
                var list = await CaiRuntimeDockerHelpers.DockerCaptureForContextAsync(
                    context,
                    ["ps", "-aq", "--filter", "label=containai.managed=true"],
                    cancellationToken).ConfigureAwait(false);
                if (list.ExitCode != 0)
                {
                    continue;
                }

                foreach (var container in list.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    targets.Add(new CaiStopTarget(context, container));
                }
            }

            return ResolutionResult<IReadOnlyList<CaiStopTarget>>.SuccessResult(targets);
        }

        var workspace = Path.GetFullPath(Directory.GetCurrentDirectory());
        var workspaceContainer = await CaiRuntimeCommandParsingHelpers
            .ResolveWorkspaceContainerNameAsync(workspace, stderr, ConfigFileNames, cancellationToken)
            .ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(workspaceContainer))
        {
            await stderr.WriteLineAsync("Usage: cai stop --all | --container <name> [--remove]").ConfigureAwait(false);
            return ResolutionResult<IReadOnlyList<CaiStopTarget>>.ErrorResult("Workspace container is not configured.");
        }

        var workspaceContexts = await CaiRuntimeDockerHelpers.FindContainerContextsAsync(workspaceContainer, cancellationToken).ConfigureAwait(false);
        if (!await TryResolveSingleTargetAsync(workspaceContexts, workspaceContainer).ConfigureAwait(false))
        {
            return ResolutionResult<IReadOnlyList<CaiStopTarget>>.ErrorResult("Unable to resolve workspace stop target.");
        }

        targets.Add(new CaiStopTarget(workspaceContexts[0], workspaceContainer));
        return ResolutionResult<IReadOnlyList<CaiStopTarget>>.SuccessResult(targets);
    }

    private async Task<bool> TryResolveSingleTargetAsync(List<string> contexts, string containerName)
    {
        if (contexts.Count == 0)
        {
            await stderr.WriteLineAsync($"Container not found: {containerName}").ConfigureAwait(false);
            return false;
        }

        if (contexts.Count > 1)
        {
            await stderr.WriteLineAsync($"Container '{containerName}' exists in multiple contexts: {string.Join(", ", contexts)}").ConfigureAwait(false);
            return false;
        }

        return true;
    }
}
