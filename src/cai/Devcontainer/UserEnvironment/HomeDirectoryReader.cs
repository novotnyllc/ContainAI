using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Devcontainer.UserEnvironment;

internal sealed class HomeDirectoryReader(
    IDevcontainerProcessHelpers processHelpers,
    Func<string, string?> environmentVariableReader)
{
    public async Task<string> ReadHomeAsync(string user, CancellationToken cancellationToken)
    {
        if (await processHelpers.CommandExistsAsync("getent", cancellationToken).ConfigureAwait(false))
        {
            var result = await processHelpers.RunProcessCaptureAsync("getent", ["passwd", user], cancellationToken).ConfigureAwait(false);
            if (result.ExitCode == 0)
            {
                var parts = result.StandardOutput.Trim().Split(':');
                if (parts.Length >= 6 && Directory.Exists(parts[5]))
                {
                    return parts[5];
                }
            }
        }

        if (string.Equals(user, "root", StringComparison.Ordinal))
        {
            return "/root";
        }

        var conventionalPath = $"/home/{user}";
        if (Directory.Exists(conventionalPath))
        {
            return conventionalPath;
        }

        return environmentVariableReader("HOME") ?? conventionalPath;
    }
}
