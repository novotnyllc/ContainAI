namespace ContainAI.Cli.Host;

internal sealed partial class CaiDoctorOperations
{
    private async Task WriteDoctorStatusAsync(
        bool outputJson,
        bool buildTemplates,
        bool dockerCli,
        bool contextExists,
        string? contextName,
        bool dockerInfo,
        bool sysboxRuntime,
        bool templateStatus)
    {
        if (outputJson)
        {
            await stdout.WriteLineAsync($"{{\"docker_cli\":{dockerCli.ToString().ToLowerInvariant()},\"context\":{contextExists.ToString().ToLowerInvariant()},\"docker_daemon\":{dockerInfo.ToString().ToLowerInvariant()},\"sysbox_runtime\":{sysboxRuntime.ToString().ToLowerInvariant()},\"templates\":{templateStatus.ToString().ToLowerInvariant()}}}").ConfigureAwait(false);
            return;
        }

        await stdout.WriteLineAsync($"Docker CLI: {(dockerCli ? "ok" : "missing")}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Context: {(contextExists ? contextName : "missing")}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Docker daemon: {(dockerInfo ? "ok" : "unreachable")}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"sysbox-runc runtime: {(sysboxRuntime ? "ok" : "missing")}").ConfigureAwait(false);
        if (buildTemplates)
        {
            await stdout.WriteLineAsync($"Templates: {(templateStatus ? "ok" : "failed")}").ConfigureAwait(false);
        }
    }
}
