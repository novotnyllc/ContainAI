namespace ContainAI.Cli.Host;

internal sealed partial class CaiDoctorOperations : CaiRuntimeSupport
{
    public CaiDoctorOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<int> RunDoctorAsync(
        bool outputJson,
        bool buildTemplates,
        bool resetLima,
        CancellationToken cancellationToken)
    {
        var resetExitCode = await TryResetLimaAsync(resetLima, cancellationToken).ConfigureAwait(false);
        if (resetExitCode.HasValue)
        {
            return resetExitCode.Value;
        }

        var dockerCli = await CommandSucceedsAsync("docker", ["--version"], cancellationToken).ConfigureAwait(false);
        var contextName = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var contextExists = !string.IsNullOrWhiteSpace(contextName);
        var dockerInfoArgs = BuildDockerInfoArgs(contextName, contextExists);
        var dockerInfo = await CommandSucceedsAsync("docker", dockerInfoArgs, cancellationToken).ConfigureAwait(false);

        var runtimeArgs = new List<string>(dockerInfoArgs)
        {
            "--format",
            "{{json .Runtimes}}",
        };
        var runtimeInfo = await RunProcessCaptureAsync("docker", runtimeArgs, cancellationToken).ConfigureAwait(false);
        var sysboxRuntime = runtimeInfo.ExitCode == 0 && runtimeInfo.StandardOutput.Contains("sysbox-runc", StringComparison.Ordinal);
        var templateStatus = await ResolveTemplateStatusAsync(buildTemplates, cancellationToken).ConfigureAwait(false);
        await WriteDoctorStatusAsync(
            outputJson,
            buildTemplates,
            dockerCli,
            contextExists,
            contextName,
            dockerInfo,
            sysboxRuntime,
            templateStatus).ConfigureAwait(false);

        return dockerCli && contextExists && dockerInfo && sysboxRuntime && templateStatus ? 0 : 1;
    }
}
