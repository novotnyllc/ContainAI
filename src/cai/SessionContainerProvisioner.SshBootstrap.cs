using System.Text;

namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerProvisioner
{
    private static async Task<ResolutionResult<bool>> EnsureSshBootstrapAsync(
        ResolvedTarget resolved,
        string sshPort,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(sshPort))
        {
            return ErrorResult<bool>("Container has no SSH port configured.");
        }

        var keyResult = await EnsureSshKeyPairAsync(cancellationToken).ConfigureAwait(false);
        if (!keyResult.Success)
        {
            return ErrorFrom<bool, bool>(keyResult);
        }

        var waitReady = await WaitForSshPortAsync(sshPort, cancellationToken).ConfigureAwait(false);
        if (!waitReady)
        {
            return ErrorResult<bool>($"SSH port {sshPort} is not ready for container '{resolved.ContainerName}'.", 12);
        }

        var publicKey = await File.ReadAllTextAsync(SessionRuntimeInfrastructure.ResolveSshPublicKeyPath(), cancellationToken).ConfigureAwait(false);
        var keyLine = publicKey.Trim();
        if (string.IsNullOrWhiteSpace(keyLine))
        {
            return ErrorResult<bool>("SSH public key is empty.", 12);
        }

        var escapedKey = SessionRuntimeInfrastructure.EscapeForSingleQuotedShell(keyLine);
        var authorize = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            resolved.Context,
            [
                "exec",
                resolved.ContainerName,
                "sh",
                "-lc",
                $"mkdir -p /home/agent/.ssh && chmod 700 /home/agent/.ssh && touch /home/agent/.ssh/authorized_keys && grep -qxF '{escapedKey}' /home/agent/.ssh/authorized_keys || printf '%s\\n' '{escapedKey}' >> /home/agent/.ssh/authorized_keys; chown -R agent:agent /home/agent/.ssh; chmod 600 /home/agent/.ssh/authorized_keys",
            ],
            cancellationToken).ConfigureAwait(false);

        if (authorize.ExitCode != 0)
        {
            return ErrorResult<bool>(
                $"Failed to install SSH public key: {SessionRuntimeInfrastructure.TrimOrFallback(authorize.StandardError, "docker exec failed")}",
                12);
        }

        var knownHosts = await UpdateKnownHostsAsync(resolved.ContainerName, sshPort, cancellationToken).ConfigureAwait(false);
        if (!knownHosts.Success)
        {
            return ErrorFrom<bool, bool>(knownHosts);
        }

        var sshConfig = await EnsureSshHostConfigAsync(resolved.ContainerName, sshPort, cancellationToken).ConfigureAwait(false);
        if (!sshConfig.Success)
        {
            return ErrorFrom<bool, bool>(sshConfig);
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }

    private static async Task<ResolutionResult<bool>> EnsureSshHostConfigAsync(string containerName, string sshPort, CancellationToken cancellationToken)
    {
        var configDir = SessionRuntimeInfrastructure.ResolveSshConfigDir();
        Directory.CreateDirectory(configDir);

        var hostConfigPath = Path.Combine(configDir, $"{containerName}.conf");
        var identityFile = SessionRuntimeInfrastructure.ResolveSshPrivateKeyPath();
        var knownHostsFile = SessionRuntimeInfrastructure.ResolveKnownHostsFilePath();

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

        var userSshConfig = Path.Combine(SessionRuntimeInfrastructure.ResolveHomeDirectory(), ".ssh", "config");
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

    private static async Task<ResolutionResult<bool>> UpdateKnownHostsAsync(string containerName, string sshPort, CancellationToken cancellationToken)
    {
        var knownHostsFile = SessionRuntimeInfrastructure.ResolveKnownHostsFilePath();
        Directory.CreateDirectory(Path.GetDirectoryName(knownHostsFile)!);
        if (!File.Exists(knownHostsFile))
        {
            await File.WriteAllTextAsync(knownHostsFile, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        var scan = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
            "ssh-keyscan",
            ["-p", sshPort, "-T", "5", "-t", "rsa,ed25519,ecdsa", SessionRuntimeConstants.SshHost],
            cancellationToken).ConfigureAwait(false);
        if (scan.ExitCode != 0 || string.IsNullOrWhiteSpace(scan.StandardOutput))
        {
            return ErrorResult<bool>("Failed to read SSH host key via ssh-keyscan.", 12);
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
            var alias = SessionRuntimeInfrastructure.ReplaceFirstToken(line, aliasHost);
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

    private static async Task<ResolutionResult<bool>> EnsureSshKeyPairAsync(CancellationToken cancellationToken)
    {
        var configDir = SessionRuntimeInfrastructure.ResolveConfigDirectory();
        Directory.CreateDirectory(configDir);

        var privateKey = SessionRuntimeInfrastructure.ResolveSshPrivateKeyPath();
        var publicKey = SessionRuntimeInfrastructure.ResolveSshPublicKeyPath();

        if (!File.Exists(privateKey) || !File.Exists(publicKey))
        {
            var keygen = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
                "ssh-keygen",
                ["-t", "ed25519", "-N", string.Empty, "-f", privateKey, "-C", "containai"],
                cancellationToken).ConfigureAwait(false);

            if (keygen.ExitCode != 0)
            {
                return ErrorResult<bool>(
                    $"Failed to generate SSH key: {SessionRuntimeInfrastructure.TrimOrFallback(keygen.StandardError, "ssh-keygen failed")}");
            }
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }

    private static async Task<bool> WaitForSshPortAsync(string sshPort, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 30; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var scan = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
                "ssh-keyscan",
                ["-p", sshPort, "-T", "2", SessionRuntimeConstants.SshHost],
                cancellationToken).ConfigureAwait(false);
            if (scan.ExitCode == 0)
            {
                return true;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken).ConfigureAwait(false);
        }

        return false;
    }
}
