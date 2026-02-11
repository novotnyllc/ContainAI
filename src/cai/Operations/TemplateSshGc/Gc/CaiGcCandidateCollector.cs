using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host;

internal interface ICaiGcCandidateCollector
{
    Task<CaiGcPruneCandidateResult> CollectAsync(TimeSpan minimumAge, CancellationToken cancellationToken);
}

internal sealed class CaiGcCandidateCollector : ICaiGcCandidateCollector
{
    private readonly TextWriter stderr;

    public CaiGcCandidateCollector(TextWriter standardError)
        => stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<CaiGcPruneCandidateResult> CollectAsync(TimeSpan minimumAge, CancellationToken cancellationToken)
    {
        var candidates = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            ["ps", "-aq", "--filter", "label=containai.managed=true", "--filter", "status=exited", "--filter", "status=created"],
            cancellationToken).ConfigureAwait(false);

        if (candidates.ExitCode != 0)
        {
            await stderr.WriteLineAsync(candidates.StandardError.Trim()).ConfigureAwait(false);
            return new CaiGcPruneCandidateResult(1, [], 0);
        }

        var containerIds = candidates.StandardOutput
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        var pruneCandidates = new List<string>();
        var failures = 0;
        foreach (var containerId in containerIds)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var inspect = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
                ["inspect", "--format", "{{.State.Status}}|{{.State.FinishedAt}}|{{.Created}}|{{with index .Config.Labels \"containai.keep\"}}{{.}}{{end}}", containerId],
                cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode != 0)
            {
                failures++;
                continue;
            }

            var inspectFields = inspect.StandardOutput.Trim().Split('|');
            if (inspectFields.Length < 4)
            {
                continue;
            }

            if (string.Equals(inspectFields[0], "running", StringComparison.Ordinal))
            {
                continue;
            }

            if (string.Equals(inspectFields[3], "true", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var referenceTime = CaiRuntimeParseAndTimeHelpers.ParseGcReferenceTime(inspectFields[1], inspectFields[2]);
            if (referenceTime is null)
            {
                continue;
            }

            if (DateTimeOffset.UtcNow - referenceTime.Value < minimumAge)
            {
                continue;
            }

            pruneCandidates.Add(containerId);
        }

        return new CaiGcPruneCandidateResult(0, pruneCandidates, failures);
    }
}
