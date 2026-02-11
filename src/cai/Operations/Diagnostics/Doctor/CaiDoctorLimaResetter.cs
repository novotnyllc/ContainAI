using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal interface ICaiDoctorLimaResetter
{
    Task<int?> TryResetLimaAsync(bool resetLima, CancellationToken cancellationToken);
}

internal sealed class CaiDoctorLimaResetter : ICaiDoctorLimaResetter
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiDoctorLimaResetter(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<int?> TryResetLimaAsync(bool resetLima, CancellationToken cancellationToken)
    {
        if (!resetLima)
        {
            return null;
        }

        if (!OperatingSystem.IsMacOS())
        {
            await stderr.WriteLineAsync("--reset-lima is only available on macOS").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Resetting Lima VM containai...").ConfigureAwait(false);
        await CaiRuntimeProcessRunner.RunProcessCaptureAsync("limactl", ["delete", "containai", "--force"], cancellationToken).ConfigureAwait(false);
        await CaiRuntimeProcessRunner.RunProcessCaptureAsync("docker", ["context", "rm", "-f", "containai-docker"], cancellationToken).ConfigureAwait(false);
        return null;
    }
}
