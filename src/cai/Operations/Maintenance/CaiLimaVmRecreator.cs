using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal sealed class CaiLimaVmRecreator : ICaiLimaVmRecreator
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiLimaVmRecreator(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<int> RecreateAsync(CancellationToken cancellationToken)
    {
        await stdout.WriteLineAsync("Recreating Lima VM 'containai'...").ConfigureAwait(false);
        await CaiRuntimeProcessRunner.RunProcessCaptureAsync("limactl", ["delete", "containai", "--force"], cancellationToken).ConfigureAwait(false);
        var start = await CaiRuntimeProcessRunner.RunProcessCaptureAsync("limactl", ["start", "containai"], cancellationToken).ConfigureAwait(false);
        if (start.ExitCode != 0)
        {
            await stderr.WriteLineAsync(start.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }
}
