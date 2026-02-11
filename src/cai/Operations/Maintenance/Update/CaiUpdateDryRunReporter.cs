namespace ContainAI.Cli.Host;

internal interface ICaiUpdateDryRunReporter
{
    Task<int> RunUpdateDryRunAsync(bool stopContainers, bool limaRecreate);
}

internal sealed class CaiUpdateDryRunReporter : ICaiUpdateDryRunReporter
{
    private readonly TextWriter stdout;

    public CaiUpdateDryRunReporter(TextWriter standardOutput)
        => stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));

    public async Task<int> RunUpdateDryRunAsync(bool stopContainers, bool limaRecreate)
    {
        await stdout.WriteLineAsync("Would pull latest base image for configured channel.").ConfigureAwait(false);
        if (stopContainers)
        {
            await stdout.WriteLineAsync("Would stop running ContainAI containers before update.").ConfigureAwait(false);
        }

        if (limaRecreate)
        {
            await stdout.WriteLineAsync("Would recreate Lima VM 'containai'.").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync("Would refresh templates and verify installation.").ConfigureAwait(false);
        return 0;
    }
}
