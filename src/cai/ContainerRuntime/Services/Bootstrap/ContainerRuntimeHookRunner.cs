using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal sealed class ContainerRuntimeHookRunner : IContainerRuntimeHookRunner
{
    private readonly IContainerRuntimeExecutionContext context;

    public ContainerRuntimeHookRunner(IContainerRuntimeExecutionContext context)
        => this.context = context ?? throw new ArgumentNullException(nameof(context));

    public async Task RunHooksAsync(
        string hooksDirectory,
        string workspaceDirectory,
        string homeDirectory,
        bool quiet,
        CancellationToken cancellationToken)
    {
        if (!Directory.Exists(hooksDirectory))
        {
            return;
        }

        var hooks = Directory.EnumerateFiles(hooksDirectory, "*.sh", SearchOption.TopDirectoryOnly)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();
        if (hooks.Length == 0)
        {
            return;
        }

        var workingDirectory = Directory.Exists(workspaceDirectory) ? workspaceDirectory : homeDirectory;
        foreach (var hook in hooks)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!context.IsExecutable(hook))
            {
                await context.StandardError.WriteLineAsync($"[WARN] Skipping non-executable hook: {hook}").ConfigureAwait(false);
                continue;
            }

            await context.LogInfoAsync(quiet, $"Running startup hook: {hook}").ConfigureAwait(false);
            var result = await context.RunProcessCaptureAsync(
                hook,
                [],
                workingDirectory,
                cancellationToken).ConfigureAwait(false);
            if (result.ExitCode != 0)
            {
                throw new InvalidOperationException($"Startup hook failed: {hook}: {result.StandardError.Trim()}");
            }
        }

        await context.LogInfoAsync(quiet, $"Completed hooks from: {hooksDirectory}").ConfigureAwait(false);
    }
}
