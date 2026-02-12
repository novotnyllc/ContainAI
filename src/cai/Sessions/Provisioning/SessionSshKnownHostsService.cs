using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal sealed class SessionSshKnownHostsService : ISessionSshKnownHostsService
{
    public async Task<ResolutionResult<bool>> UpdateKnownHostsAsync(string containerName, string sshPort, CancellationToken cancellationToken)
    {
        var knownHostsFile = SessionRuntimePathHelpers.ResolveKnownHostsFilePath();
        Directory.CreateDirectory(Path.GetDirectoryName(knownHostsFile)!);
        if (!File.Exists(knownHostsFile))
        {
            await File.WriteAllTextAsync(knownHostsFile, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        var scan = await SessionRuntimeProcessHelpers.RunProcessCaptureAsync(
            "ssh-keyscan",
            ["-p", sshPort, "-T", "5", "-t", "rsa,ed25519,ecdsa", SessionRuntimeConstants.SshHost],
            cancellationToken).ConfigureAwait(false);
        if (scan.ExitCode != 0 || string.IsNullOrWhiteSpace(scan.StandardOutput))
        {
            return ResolutionResult<bool>.ErrorResult("Failed to read SSH host key via ssh-keyscan.", 12);
        }

        var lines = scan.StandardOutput
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(static line => !line.StartsWith('#'))
            .Distinct(StringComparer.Ordinal)
            .ToArray();

        var existing = new HashSet<string>(StringComparer.Ordinal);
        foreach (var line in await File.ReadAllLinesAsync(knownHostsFile, cancellationToken).ConfigureAwait(false))
        {
            if (!string.IsNullOrWhiteSpace(line))
            {
                existing.Add(line.Trim());
            }
        }

        var additions = new List<string>();
        foreach (var line in lines)
        {
            if (existing.Add(line))
            {
                additions.Add(line);
            }

            var aliasHost = $"[{containerName}]:{sshPort}";
            var alias = SessionRuntimeTextHelpers.ReplaceFirstToken(line, aliasHost);
            if (existing.Add(alias))
            {
                additions.Add(alias);
            }
        }

        if (additions.Count > 0)
        {
            await File.AppendAllLinesAsync(knownHostsFile, additions, cancellationToken).ConfigureAwait(false);
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }
}
