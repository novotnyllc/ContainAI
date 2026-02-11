using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface IImportDataVolumeEnsurer
{
    Task<int> EnsureVolumeAsync(string volume, bool dryRun, CancellationToken cancellationToken);
}

internal sealed class ImportDataVolumeEnsurer : IImportDataVolumeEnsurer
{
    private readonly TextWriter stderr;

    public ImportDataVolumeEnsurer(TextWriter standardError)
        => stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<int> EnsureVolumeAsync(string volume, bool dryRun, CancellationToken cancellationToken)
    {
        if (dryRun)
        {
            return 0;
        }

        var ensureVolume = await CaiRuntimeDockerHelpers
            .DockerCaptureAsync(["volume", "create", volume], cancellationToken)
            .ConfigureAwait(false);

        if (ensureVolume.ExitCode == 0)
        {
            return 0;
        }

        await stderr.WriteLineAsync(ensureVolume.StandardError.Trim()).ConfigureAwait(false);
        return 1;
    }
}
