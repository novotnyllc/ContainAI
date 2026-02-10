namespace ContainAI.Cli.Host;

internal sealed class CaiDoctorOperations : CaiRuntimeSupport
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
        if (resetLima)
        {
            if (!OperatingSystem.IsMacOS())
            {
                await stderr.WriteLineAsync("--reset-lima is only available on macOS").ConfigureAwait(false);
                return 1;
            }

            await stdout.WriteLineAsync("Resetting Lima VM containai...").ConfigureAwait(false);
            await RunProcessCaptureAsync("limactl", ["delete", "containai", "--force"], cancellationToken).ConfigureAwait(false);
            await RunProcessCaptureAsync("docker", ["context", "rm", "-f", "containai-docker"], cancellationToken).ConfigureAwait(false);
        }

        var dockerCli = await CommandSucceedsAsync("docker", ["--version"], cancellationToken).ConfigureAwait(false);
        var contextName = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var contextExists = !string.IsNullOrWhiteSpace(contextName);
        var dockerInfoArgs = new List<string>();
        if (contextExists)
        {
            dockerInfoArgs.Add("--context");
            dockerInfoArgs.Add(contextName!);
        }

        dockerInfoArgs.Add("info");
        var dockerInfo = await CommandSucceedsAsync("docker", dockerInfoArgs, cancellationToken).ConfigureAwait(false);

        var runtimeArgs = new List<string>(dockerInfoArgs)
        {
            "--format",
            "{{json .Runtimes}}",
        };
        var runtimeInfo = await RunProcessCaptureAsync("docker", runtimeArgs, cancellationToken).ConfigureAwait(false);
        var sysboxRuntime = runtimeInfo.ExitCode == 0 && runtimeInfo.StandardOutput.Contains("sysbox-runc", StringComparison.Ordinal);
        var templateStatus = true;
        if (buildTemplates)
        {
            templateStatus = await ValidateTemplatesAsync(cancellationToken).ConfigureAwait(false);
        }

        if (outputJson)
        {
            await stdout.WriteLineAsync($"{{\"docker_cli\":{dockerCli.ToString().ToLowerInvariant()},\"context\":{contextExists.ToString().ToLowerInvariant()},\"docker_daemon\":{dockerInfo.ToString().ToLowerInvariant()},\"sysbox_runtime\":{sysboxRuntime.ToString().ToLowerInvariant()},\"templates\":{templateStatus.ToString().ToLowerInvariant()}}}").ConfigureAwait(false);
        }
        else
        {
            await stdout.WriteLineAsync($"Docker CLI: {(dockerCli ? "ok" : "missing")}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Context: {(contextExists ? contextName : "missing")}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Docker daemon: {(dockerInfo ? "ok" : "unreachable")}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"sysbox-runc runtime: {(sysboxRuntime ? "ok" : "missing")}").ConfigureAwait(false);
            if (buildTemplates)
            {
                await stdout.WriteLineAsync($"Templates: {(templateStatus ? "ok" : "failed")}").ConfigureAwait(false);
            }
        }

        return dockerCli && contextExists && dockerInfo && sysboxRuntime && templateStatus ? 0 : 1;
    }

    private static async Task<bool> ValidateTemplatesAsync(CancellationToken cancellationToken)
    {
        var templatesRoot = ResolveTemplatesDirectory();
        if (!Directory.Exists(templatesRoot))
        {
            return false;
        }

        foreach (var dockerfile in Directory.EnumerateFiles(templatesRoot, "Dockerfile", SearchOption.AllDirectories))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var directory = Path.GetDirectoryName(dockerfile)!;
            var imageName = $"containai-template-check-{Path.GetFileName(directory)}";
            var build = await DockerCaptureAsync(["build", "-q", "-f", dockerfile, "-t", imageName, directory], cancellationToken).ConfigureAwait(false);
            if (build.ExitCode != 0)
            {
                return false;
            }
        }

        return true;
    }
}
