using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal sealed class CaiDockerCommandForwarder : ICaiDockerCommandForwarder
{
    public async Task<int> RunAsync(IReadOnlyList<string> dockerArguments, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(dockerArguments);

        var executable = CaiRuntimePathResolutionHelpers.IsExecutableOnPath("containai-docker")
            ? "containai-docker"
            : "docker";

        var dockerArgs = new List<string>();
        if (string.Equals(executable, "docker", StringComparison.Ordinal))
        {
            var context = await CaiRuntimeDockerHelpers.ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(context))
            {
                dockerArgs.Add("--context");
                dockerArgs.Add(context);
            }
        }

        dockerArgs.AddRange(dockerArguments);

        return await CaiRuntimeProcessRunner.RunProcessInteractiveAsync(executable, dockerArgs, cancellationToken).ConfigureAwait(false);
    }
}
