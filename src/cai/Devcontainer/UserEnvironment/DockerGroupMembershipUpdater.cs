using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Devcontainer.UserEnvironment;

internal sealed class DockerGroupMembershipUpdater(
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
