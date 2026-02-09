namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private async Task LoadEnvFileAsync(string envFilePath, bool quiet)
    {
        if (await IsSymlinkAsync(envFilePath).ConfigureAwait(false))
        {
            await stderr.WriteLineAsync("[WARN] .env is symlink - skipping").ConfigureAwait(false);
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
            await stderr.WriteLineAsync("[WARN] .env unreadable - skipping").ConfigureAwait(false);
            return;
        }
        catch (UnauthorizedAccessException)
        {
            await stderr.WriteLineAsync("[WARN] .env unreadable - skipping").ConfigureAwait(false);
            return;
        }

        await LogInfoAsync(quiet, "Loading environment from .env").ConfigureAwait(false);

        var lines = await File.ReadAllLinesAsync(envFilePath).ConfigureAwait(false);
        for (var index = 0; index < lines.Length; index++)
        {
            var line = lines[index].TrimEnd('\r');
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            if (line.TrimStart().StartsWith('#'))
            {
                continue;
            }

            if (line.StartsWith("export ", StringComparison.Ordinal))
            {
                line = line[7..].TrimStart();
            }

            var separator = line.IndexOf('=', StringComparison.Ordinal);
            if (separator <= 0)
            {
                continue;
            }

            var key = line[..separator];
            var value = line[(separator + 1)..];
            if (!IsValidEnvKey(key))
            {
                await stderr.WriteLineAsync($"[WARN] line {index + 1}: invalid key '{key}' - skipping").ConfigureAwait(false);
                continue;
            }

            if (Environment.GetEnvironmentVariable(key) is null)
            {
                Environment.SetEnvironmentVariable(key, value);
            }
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
