using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeEnvironmentFileLoader
{
    Task LoadEnvFileAsync(string envFilePath, bool quiet);
}

internal sealed class ContainerRuntimeEnvironmentFileLoader : IContainerRuntimeEnvironmentFileLoader
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

    private async Task ApplyEnvLineIfValidAsync(string rawLine, int lineNumber)
    {
        var line = rawLine.TrimEnd('\r');
        if (string.IsNullOrWhiteSpace(line) || line.TrimStart().StartsWith('#'))
        {
            return;
        }

        if (line.StartsWith("export ", StringComparison.Ordinal))
        {
            line = line[7..].TrimStart();
        }

        var separator = line.IndexOf('=', StringComparison.Ordinal);
        if (separator <= 0)
        {
            return;
        }

        var key = line[..separator];
        var value = line[(separator + 1)..];
        if (!IsValidEnvKey(key))
        {
            await context.StandardError.WriteLineAsync($"[WARN] line {lineNumber}: invalid key '{key}' - skipping").ConfigureAwait(false);
            return;
        }

        if (Environment.GetEnvironmentVariable(key) is null)
        {
            Environment.SetEnvironmentVariable(key, value);
        }
    }

    private static bool IsValidEnvKey(string key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            return false;
        }

        if (!(char.IsLetter(key[0]) || key[0] == '_'))
        {
            return false;
        }

        for (var index = 1; index < key.Length; index++)
        {
            var c = key[index];
            if (!(char.IsLetterOrDigit(c) || c == '_'))
            {
                return false;
            }
        }

        return true;
    }
}
