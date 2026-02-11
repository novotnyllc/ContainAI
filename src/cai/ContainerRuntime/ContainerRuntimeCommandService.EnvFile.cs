using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeEnvironmentFileLoader
{
    Task LoadEnvFileAsync(string envFilePath, bool quiet);
}

internal sealed partial class ContainerRuntimeEnvironmentFileLoader : IContainerRuntimeEnvironmentFileLoader
{
    private readonly IContainerRuntimeExecutionContext context;

    public ContainerRuntimeEnvironmentFileLoader(IContainerRuntimeExecutionContext context)
        => this.context = context ?? throw new ArgumentNullException(nameof(context));

    public async Task LoadEnvFileAsync(string envFilePath, bool quiet)
    {
        if (await context.IsSymlinkAsync(envFilePath).ConfigureAwait(false))
        {
            await context.StandardError.WriteLineAsync("[WARN] .env is symlink - skipping").ConfigureAwait(false);
            return;
        }

        if (!File.Exists(envFilePath))
        {
            return;
        }

        try
        {
            using var stream = File.OpenRead(envFilePath);
        }
        catch (IOException)
        {
            await context.StandardError.WriteLineAsync("[WARN] .env unreadable - skipping").ConfigureAwait(false);
            return;
        }
        catch (UnauthorizedAccessException)
        {
            await context.StandardError.WriteLineAsync("[WARN] .env unreadable - skipping").ConfigureAwait(false);
            return;
        }

        await context.LogInfoAsync(quiet, "Loading environment from .env").ConfigureAwait(false);

        var lines = await File.ReadAllLinesAsync(envFilePath).ConfigureAwait(false);
        for (var index = 0; index < lines.Length; index++)
        {
            await ApplyEnvLineIfValidAsync(lines[index], index + 1).ConfigureAwait(false);
        }
    }
}
