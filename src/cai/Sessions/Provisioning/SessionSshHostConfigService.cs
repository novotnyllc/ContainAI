using System.Text;
using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal sealed class SessionSshHostConfigService : ISessionSshHostConfigService
{
    public async Task<ResolutionResult<bool>> EnsureSshHostConfigAsync(string containerName, string sshPort, CancellationToken cancellationToken)
    {
        var configDir = SessionRuntimePathHelpers.ResolveSshConfigDir();
        Directory.CreateDirectory(configDir);

        var hostConfigPath = Path.Combine(configDir, $"{containerName}.conf");
        var identityFile = SessionRuntimePathHelpers.ResolveSshPrivateKeyPath();
        var knownHostsFile = SessionRuntimePathHelpers.ResolveKnownHostsFilePath();

        var hostEntry = $"""
Host {containerName}
    HostName {SessionRuntimeConstants.SshHost}
    Port {sshPort}
    User agent
    IdentityFile {identityFile}
    IdentitiesOnly yes
    UserKnownHostsFile {knownHostsFile}
    StrictHostKeyChecking accept-new
    AddressFamily inet
""";

        await File.WriteAllTextAsync(hostConfigPath, hostEntry, cancellationToken).ConfigureAwait(false);

        var userSshConfig = Path.Combine(SessionRuntimePathHelpers.ResolveHomeDirectory(), ".ssh", "config");
        Directory.CreateDirectory(Path.GetDirectoryName(userSshConfig)!);
        if (!File.Exists(userSshConfig))
        {
            await File.WriteAllTextAsync(userSshConfig, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        var includeLine = $"Include {configDir}/*.conf";
        var configText = await File.ReadAllTextAsync(userSshConfig, cancellationToken).ConfigureAwait(false);
        if (!configText.Contains(includeLine, StringComparison.Ordinal))
        {
            var builder = new StringBuilder(configText.TrimEnd());
            if (builder.Length > 0)
            {
                builder.AppendLine();
            }

            builder.AppendLine(includeLine);
            await File.WriteAllTextAsync(userSshConfig, builder.ToString(), cancellationToken).ConfigureAwait(false);
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }
}
