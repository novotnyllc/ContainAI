using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionSshKeyPairService
{
    Task<ResolutionResult<bool>> EnsureSshKeyPairAsync(CancellationToken cancellationToken);
}

internal sealed class SessionSshKeyPairService : ISessionSshKeyPairService
{
    public async Task<ResolutionResult<bool>> EnsureSshKeyPairAsync(CancellationToken cancellationToken)
    {
        var configDir = SessionRuntimePathHelpers.ResolveConfigDirectory();
        Directory.CreateDirectory(configDir);

        var privateKey = SessionRuntimePathHelpers.ResolveSshPrivateKeyPath();
        var publicKey = SessionRuntimePathHelpers.ResolveSshPublicKeyPath();

        if (!File.Exists(privateKey) || !File.Exists(publicKey))
        {
            var keygen = await SessionRuntimeProcessHelpers.RunProcessCaptureAsync(
                "ssh-keygen",
                ["-t", "ed25519", "-N", string.Empty, "-f", privateKey, "-C", "containai"],
                cancellationToken).ConfigureAwait(false);

            if (keygen.ExitCode != 0)
            {
                return ResolutionResult<bool>.ErrorResult(
                    $"Failed to generate SSH key: {SessionRuntimeTextHelpers.TrimOrFallback(keygen.StandardError, "ssh-keygen failed")}");
            }
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }
}
