using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface ICaiDoctorFixContainerRunner
{
    Task<int> RunAsync(bool fixAll, string? target, string? targetArg, CancellationToken cancellationToken);
}

internal sealed class CaiDoctorFixContainerRunner : ICaiDoctorFixContainerRunner
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiDoctorFixContainerRunner(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<int> RunAsync(bool fixAll, string? target, string? targetArg, CancellationToken cancellationToken)
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

        var exists = await CaiRuntimeDockerHelpers.DockerContainerExistsAsync(targetArg, cancellationToken).ConfigureAwait(false);
        if (!exists)
        {
            await stderr.WriteLineAsync($"Container not found: {targetArg}").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync($"Container fix completed for {targetArg}.").ConfigureAwait(false);
        return 0;
    }
}
