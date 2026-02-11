namespace ContainAI.Cli.Host;

internal interface ICaiDoctorStatusWriter
{
    Task WriteAsync(bool outputJson, bool buildTemplates, CaiDoctorRuntimeProbeResult runtimeProbe, bool templateStatus);
}

internal sealed class CaiDoctorStatusWriter : ICaiDoctorStatusWriter
{
    private readonly TextWriter stdout;

    public CaiDoctorStatusWriter(TextWriter standardOutput)
        => stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));

    public async Task WriteAsync(bool outputJson, bool buildTemplates, CaiDoctorRuntimeProbeResult runtimeProbe, bool templateStatus)
    {
        if (outputJson)
        {
            await stdout.WriteLineAsync(
                    $"{{\"docker_cli\":{runtimeProbe.DockerCli.ToString().ToLowerInvariant()},\"context\":{runtimeProbe.ContextExists.ToString().ToLowerInvariant()},\"docker_daemon\":{runtimeProbe.DockerInfo.ToString().ToLowerInvariant()},\"sysbox_runtime\":{runtimeProbe.SysboxRuntime.ToString().ToLowerInvariant()},\"templates\":{templateStatus.ToString().ToLowerInvariant()}}}")
                .ConfigureAwait(false);
            return;
        }

        await stdout.WriteLineAsync($"Docker CLI: {(runtimeProbe.DockerCli ? "ok" : "missing")}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Context: {(runtimeProbe.ContextExists ? runtimeProbe.ContextName : "missing")}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Docker daemon: {(runtimeProbe.DockerInfo ? "ok" : "unreachable")}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"sysbox-runc runtime: {(runtimeProbe.SysboxRuntime ? "ok" : "missing")}").ConfigureAwait(false);
        if (buildTemplates)
        {
            await stdout.WriteLineAsync($"Templates: {(templateStatus ? "ok" : "failed")}").ConfigureAwait(false);
        }
    }
}
