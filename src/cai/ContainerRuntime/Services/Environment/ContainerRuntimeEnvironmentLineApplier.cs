using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal sealed class ContainerRuntimeEnvironmentLineApplier(
    IContainerRuntimeExecutionContext context) : IContainerRuntimeEnvironmentLineApplier
{
    public async Task ApplyLineIfValidAsync(string rawLine, int lineNumber)
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
        if (!ContainerRuntimeEnvironmentVariableKeyValidator.IsValid(key))
        {
            await context.StandardError.WriteLineAsync($"[WARN] line {lineNumber}: invalid key '{key}' - skipping").ConfigureAwait(false);
            return;
        }

        if (Environment.GetEnvironmentVariable(key) is null)
        {
            Environment.SetEnvironmentVariable(key, value);
        }
    }
}
