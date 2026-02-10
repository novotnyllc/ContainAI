namespace ContainAI.Cli.Host;

internal interface IDevcontainerUserEnvironmentSetup
{
    Task<string> DetectUserHomeAsync(string remoteUser, CancellationToken cancellationToken);

    Task AddUserToDockerGroupIfPresentAsync(string user, CancellationToken cancellationToken);
}

internal sealed class DevcontainerUserEnvironmentSetup : IDevcontainerUserEnvironmentSetup
{
    private readonly DockerGroupMembershipUpdater dockerGroupMembershipUpdater;
    private readonly HomeDirectoryReader homeDirectoryReader;
    private readonly UserResolver userResolver;

    public DevcontainerUserEnvironmentSetup(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        Func<string, string?> environmentVariableReader)
    {
        var resolvedProcessHelpers = processHelpers ?? throw new ArgumentNullException(nameof(processHelpers));
        var resolvedEnvironmentVariableReader = environmentVariableReader ?? throw new ArgumentNullException(nameof(environmentVariableReader));
        var resolvedStandardOutput = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));

        userResolver = new UserResolver(resolvedProcessHelpers, resolvedEnvironmentVariableReader);
        homeDirectoryReader = new HomeDirectoryReader(resolvedProcessHelpers, resolvedEnvironmentVariableReader);
        dockerGroupMembershipUpdater = new DockerGroupMembershipUpdater(resolvedProcessHelpers, resolvedStandardOutput, userResolver);
    }

    public async Task<string> DetectUserHomeAsync(string remoteUser, CancellationToken cancellationToken)
    {
        var candidate = await userResolver.ResolveCandidateAsync(remoteUser, cancellationToken).ConfigureAwait(false);
        return await homeDirectoryReader.ReadHomeAsync(candidate, cancellationToken).ConfigureAwait(false);
    }

    public Task AddUserToDockerGroupIfPresentAsync(string user, CancellationToken cancellationToken) =>
        dockerGroupMembershipUpdater.AddUserToDockerGroupIfPresentAsync(user, cancellationToken);

    private sealed class UserResolver(
        IDevcontainerProcessHelpers processHelpers,
        Func<string, string?> environmentVariableReader)
    {
        public async Task<string> ResolveCandidateAsync(string remoteUser, CancellationToken cancellationToken)
        {
            var candidate = remoteUser;
            if (string.Equals(candidate, "auto", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(candidate))
            {
                candidate = await UserExistsAsync("vscode", cancellationToken).ConfigureAwait(false) ? "vscode"
                    : await UserExistsAsync("node", cancellationToken).ConfigureAwait(false) ? "node"
                    : environmentVariableReader("USER") ?? "root";
            }

            return candidate;
        }

        public async Task<bool> UserExistsAsync(string user, CancellationToken cancellationToken)
        {
            var result = await processHelpers.RunProcessCaptureAsync("id", ["-u", user], cancellationToken).ConfigureAwait(false);
            return result.ExitCode == 0;
        }
    }

    private sealed class HomeDirectoryReader(
        IDevcontainerProcessHelpers processHelpers,
        Func<string, string?> environmentVariableReader)
    {
        public async Task<string> ReadHomeAsync(string user, CancellationToken cancellationToken)
        {
            if (await processHelpers.CommandExistsAsync("getent", cancellationToken).ConfigureAwait(false))
            {
                var result = await processHelpers.RunProcessCaptureAsync("getent", ["passwd", user], cancellationToken).ConfigureAwait(false);
                if (result.ExitCode == 0)
                {
                    var parts = result.StandardOutput.Trim().Split(':');
                    if (parts.Length >= 6 && Directory.Exists(parts[5]))
                    {
                        return parts[5];
                    }
                }
            }

            if (string.Equals(user, "root", StringComparison.Ordinal))
            {
                return "/root";
            }

            var conventionalPath = $"/home/{user}";
            if (Directory.Exists(conventionalPath))
            {
                return conventionalPath;
            }

            return environmentVariableReader("HOME") ?? conventionalPath;
        }
    }

    private sealed class DockerGroupMembershipUpdater(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        UserResolver userResolver)
    {
        public async Task AddUserToDockerGroupIfPresentAsync(string user, CancellationToken cancellationToken)
        {
            if (!await userResolver.UserExistsAsync(user, cancellationToken).ConfigureAwait(false))
            {
                return;
            }

            await processHelpers.RunAsRootAsync("usermod", ["-aG", "docker", user], cancellationToken).ConfigureAwait(false);
            await standardOutput.WriteLineAsync($"    Added {user} to docker group").ConfigureAwait(false);
        }
    }
}
