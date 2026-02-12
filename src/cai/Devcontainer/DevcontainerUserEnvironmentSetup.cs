using ContainAI.Cli.Host.Devcontainer.UserEnvironment;

namespace ContainAI.Cli.Host.Devcontainer;

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
}
