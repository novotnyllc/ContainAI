using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Devcontainer.UserEnvironment;

internal sealed class UserResolver(
    IDevcontainerProcessHelpers processHelpers,
    Func<string, string?> environmentVariableReader)
{
    public async Task<string> ResolveCandidateAsync(string remoteUser, CancellationToken cancellationToken)
    {
        var candidate = remoteUser;
        if (string.Equals(candidate, "auto", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(candidate))
        {
            candidate = await UserExistsAsync("vscode", cancellationToken).ConfigureAwait(false) ? "vscode"
                : await UserExistsAsync("node", cancellationToken).ConfigureAwait(false) ? "node"
                : environmentVariableReader("USER") ?? "root";
        }

        return candidate;
    }

    public async Task<bool> UserExistsAsync(string user, CancellationToken cancellationToken)
    {
        var result = await processHelpers.RunProcessCaptureAsync("id", ["-u", user], cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }
}
