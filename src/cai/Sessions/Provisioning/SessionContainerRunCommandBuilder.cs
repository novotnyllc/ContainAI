using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionContainerRunCommandBuilder
{
    IReadOnlyList<string> BuildCommand(SessionCommandOptions options, ResolvedTarget resolved, string sshPort, string image);
}

internal sealed class SessionContainerRunCommandBuilder : ISessionContainerRunCommandBuilder
{
    public IReadOnlyList<string> BuildCommand(SessionCommandOptions options, ResolvedTarget resolved, string sshPort, string image)
    {
        var dockerArgs = new List<string>
        {
            "run",
            "--runtime=sysbox-runc",
            "--name", resolved.ContainerName,
            "--hostname", SessionRuntimeTextHelpers.SanitizeHostname(resolved.ContainerName),
            "--label", $"{SessionRuntimeConstants.ManagedLabelKey}={SessionRuntimeConstants.ManagedLabelValue}",
            "--label", $"{SessionRuntimeConstants.WorkspaceLabelKey}={resolved.Workspace}",
            "--label", $"{SessionRuntimeConstants.DataVolumeLabelKey}={resolved.DataVolume}",
            "--label", $"{SessionRuntimeConstants.SshPortLabelKey}={sshPort}",
            "-p", $"{sshPort}:22",
            "-d",
            "--stop-timeout", "100",
            "-v", $"{resolved.DataVolume}:/mnt/agent-data",
            "-v", $"{resolved.Workspace}:/home/agent/workspace",
            "-e", $"CAI_HOST_WORKSPACE={resolved.Workspace}",
            "-e", $"TZ={SessionRuntimeSystemHelpers.ResolveHostTimeZone()}",
            "-w", "/home/agent/workspace",
        };

        if (!string.IsNullOrWhiteSpace(options.Memory))
        {
            dockerArgs.Add("--memory");
            dockerArgs.Add(options.Memory);
            dockerArgs.Add("--memory-swap");
            dockerArgs.Add(options.Memory);
        }

        if (!string.IsNullOrWhiteSpace(options.Cpus))
        {
            dockerArgs.Add("--cpus");
            dockerArgs.Add(options.Cpus);
        }

        if (!string.IsNullOrWhiteSpace(options.Template))
        {
            dockerArgs.Add("--label");
            dockerArgs.Add($"ai.containai.template={options.Template}");
        }

        dockerArgs.Add(image);
        return dockerArgs;
    }
}
