namespace ContainAI.Cli.Host;

internal sealed partial class CaiDiagnosticsAndSetupOperations
{
    public static async Task<int> RunDockerAsync(IReadOnlyList<string> dockerArguments, CancellationToken cancellationToken)
    {
        var executable = IsExecutableOnPath("containai-docker")
            ? "containai-docker"
            : "docker";

        var dockerArgs = new List<string>();
        if (string.Equals(executable, "docker", StringComparison.Ordinal))
        {
            var context = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(context))
            {
                dockerArgs.Add("--context");
                dockerArgs.Add(context);
            }
        }

        foreach (var argument in dockerArguments)
        {
            dockerArgs.Add(argument);
        }

        return await RunProcessInteractiveAsync(executable, dockerArgs, cancellationToken).ConfigureAwait(false);
    }
}
