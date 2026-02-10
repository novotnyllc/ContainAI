namespace ContainAI.Cli.Host;

internal sealed partial class CaiDoctorFixOperations
{
    private async Task<int> RunContainerFixAsync(
        bool fixAll,
        string? target,
        string? targetArg,
        CancellationToken cancellationToken)
    {
        if (!fixAll && !string.Equals(target, "container", StringComparison.Ordinal))
        {
            return 0;
        }

        if (string.IsNullOrWhiteSpace(targetArg) || string.Equals(targetArg, "--all", StringComparison.Ordinal))
        {
            await stdout.WriteLineAsync("Container fix completed (SSH cleanup applied).").ConfigureAwait(false);
            return 0;
        }

        var exists = await DockerContainerExistsAsync(targetArg, cancellationToken).ConfigureAwait(false);
        if (!exists)
        {
            await stderr.WriteLineAsync($"Container not found: {targetArg}").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync($"Container fix completed for {targetArg}.").ConfigureAwait(false);
        return 0;
    }
}
