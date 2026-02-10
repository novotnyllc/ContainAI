using System.Net.NetworkInformation;

namespace ContainAI.Cli.Host;

internal interface ISessionSshPortAllocator
{
    Task<ResolutionResult<string>> AllocateSshPortAsync(string context, CancellationToken cancellationToken);
}

internal sealed class SessionSshPortAllocator : ISessionSshPortAllocator
{
    public async Task<ResolutionResult<string>> AllocateSshPortAsync(string context, CancellationToken cancellationToken)
    {
        var reservedPorts = new HashSet<int>();

        var reserved = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["ps", "-a", "--filter", $"label={SessionRuntimeConstants.ManagedLabelKey}={SessionRuntimeConstants.ManagedLabelValue}", "--format", $"{{{{index .Labels \"{SessionRuntimeConstants.SshPortLabelKey}\"}}}}"],
            cancellationToken).ConfigureAwait(false);
        if (reserved.ExitCode == 0)
        {
            foreach (var line in reserved.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                if (int.TryParse(line, out var parsed))
                {
                    reservedPorts.Add(parsed);
                }
            }
        }

        foreach (var used in await GetHostUsedPortsAsync(cancellationToken).ConfigureAwait(false))
        {
            reservedPorts.Add(used);
        }

        for (var port = SessionRuntimeConstants.SshPortRangeStart; port <= SessionRuntimeConstants.SshPortRangeEnd; port++)
        {
            if (!reservedPorts.Contains(port))
            {
                return ResolutionResult<string>.SuccessResult(port.ToString());
            }
        }

        return ResolutionResult<string>.ErrorResult(
            $"No SSH ports available in range {SessionRuntimeConstants.SshPortRangeStart}-{SessionRuntimeConstants.SshPortRangeEnd}.");
    }

    private static async Task<HashSet<int>> GetHostUsedPortsAsync(CancellationToken cancellationToken)
    {
        var ports = new HashSet<int>();

        var ss = await SessionRuntimeInfrastructure.RunProcessCaptureAsync("ss", ["-Htan"], cancellationToken).ConfigureAwait(false);
        if (ss.ExitCode == 0)
        {
            SessionRuntimeInfrastructure.ParsePortsFromSocketTable(ss.StandardOutput, ports);
            return ports;
        }

        var netstat = await SessionRuntimeInfrastructure.RunProcessCaptureAsync("netstat", ["-tan"], cancellationToken).ConfigureAwait(false);
        if (netstat.ExitCode == 0)
        {
            SessionRuntimeInfrastructure.ParsePortsFromSocketTable(netstat.StandardOutput, ports);
        }

        var listeners = IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners();
        foreach (var listener in listeners)
        {
            ports.Add(listener.Port);
        }

        return ports;
    }
}
