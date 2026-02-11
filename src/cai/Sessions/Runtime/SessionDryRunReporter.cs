namespace ContainAI.Cli.Host;

internal sealed class SessionDryRunReporter(TextWriter standardOutput)
{
    private readonly TextWriter stdout = standardOutput;

    public async Task WriteAsync(SessionCommandOptions options, ResolvedTarget resolved, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await stdout.WriteLineAsync("DRY_RUN=true").ConfigureAwait(false);
        await stdout.WriteLineAsync($"MODE={options.Mode.ToString().ToLowerInvariant()}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"CONTAINER={resolved.ContainerName}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"WORKSPACE={resolved.Workspace}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"DATA_VOLUME={resolved.DataVolume}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"DOCKER_CONTEXT={resolved.Context}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"FRESH={options.Fresh.ToString().ToLowerInvariant()}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"RESET={options.Reset.ToString().ToLowerInvariant()}").ConfigureAwait(false);

        if (options.Mode == SessionMode.Run)
        {
            var command = options.CommandArgs.Count == 0 ? "claude" : string.Join(" ", options.CommandArgs);
            await stdout.WriteLineAsync($"COMMAND={command}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"DETACHED={options.Detached.ToString().ToLowerInvariant()}").ConfigureAwait(false);
            return;
        }

        if (options.Mode == SessionMode.Exec)
        {
            await stdout.WriteLineAsync($"COMMAND={string.Join(" ", options.CommandArgs)}").ConfigureAwait(false);
        }
    }
}
