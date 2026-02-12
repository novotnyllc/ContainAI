using ContainAI.Cli.Host.Sessions.Infrastructure;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace;

internal sealed class SessionTargetContainerNameGenerationService : ISessionTargetContainerNameGenerationService
{
    private readonly ISessionRuntimeOperations runtimeOperations;

    public SessionTargetContainerNameGenerationService()
        : this(new SessionRuntimeOperations())
    {
    }

    internal SessionTargetContainerNameGenerationService(ISessionRuntimeOperations sessionRuntimeOperations)
        => runtimeOperations = sessionRuntimeOperations ?? throw new ArgumentNullException(nameof(sessionRuntimeOperations));

    public async Task<string> GenerateContainerNameAsync(string workspace, CancellationToken cancellationToken)
    {
        var repoName = Path.GetFileName(Path.TrimEndingDirectorySeparator(workspace));
        if (string.IsNullOrWhiteSpace(repoName))
        {
            repoName = "repo";
        }

        var branchName = "nogit";
        var gitProbe = await runtimeOperations.RunProcessCaptureAsync(
            "git",
            ["-C", workspace, "rev-parse", "--is-inside-work-tree"],
            cancellationToken).ConfigureAwait(false);
        if (gitProbe.ExitCode == 0)
        {
            var branch = await runtimeOperations.RunProcessCaptureAsync(
                "git",
                ["-C", workspace, "rev-parse", "--abbrev-ref", "HEAD"],
                cancellationToken).ConfigureAwait(false);
            if (branch.ExitCode == 0)
            {
                var value = branch.StandardOutput.Trim();
                branchName = string.IsNullOrWhiteSpace(value) || string.Equals(value, "HEAD", StringComparison.Ordinal) ? "detached" : value;
            }
            else
            {
                branchName = "detached";
            }
        }

        return ContainerNameGenerator.Compose(repoName, branchName);
    }
}
