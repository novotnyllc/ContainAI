using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal interface ICaiDoctorRuntimeProbe
{
    Task<CaiDoctorRuntimeProbeResult> ProbeAsync(CancellationToken cancellationToken);
}

internal sealed class CaiDoctorRuntimeProbe : ICaiDoctorRuntimeProbe
{
    public async Task<CaiDoctorRuntimeProbeResult> ProbeAsync(CancellationToken cancellationToken)
    {
        var dockerCli = await CaiRuntimeProcessRunner.CommandSucceedsAsync("docker", ["--version"], cancellationToken).ConfigureAwait(false);
        var contextName = await CaiRuntimeDockerHelpers.ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var contextExists = !string.IsNullOrWhiteSpace(contextName);

        var dockerInfoArgs = BuildDockerInfoArgs(contextName, contextExists);
        var dockerInfo = await CaiRuntimeProcessRunner.CommandSucceedsAsync("docker", dockerInfoArgs, cancellationToken).ConfigureAwait(false);

        var runtimeArgs = new List<string>(dockerInfoArgs)
        {
            "--format",
            "{{json .Runtimes}}",
        };

        var runtimeInfo = await CaiRuntimeProcessRunner.RunProcessCaptureAsync("docker", runtimeArgs, cancellationToken).ConfigureAwait(false);
        var sysboxRuntime = runtimeInfo.ExitCode == 0 && runtimeInfo.StandardOutput.Contains("sysbox-runc", StringComparison.Ordinal);

        return new CaiDoctorRuntimeProbeResult(dockerCli, contextExists, contextName, dockerInfo, sysboxRuntime);
    }

    private static List<string> BuildDockerInfoArgs(string? contextName, bool contextExists)
    {
        var dockerInfoArgs = new List<string>();
        if (contextExists)
        {
            dockerInfoArgs.Add("--context");
            dockerInfoArgs.Add(contextName!);
        }

        dockerInfoArgs.Add("info");
        return dockerInfoArgs;
    }
}

internal readonly record struct CaiDoctorRuntimeProbeResult(
    bool DockerCli,
    bool ContextExists,
    string? ContextName,
    bool DockerInfo,
    bool SysboxRuntime);
