namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal sealed partial class ContainerRuntimeEnvironmentFileLoader
{
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
