namespace ContainAI.Cli.Host;

internal interface ISessionSshKeyPairService
{
    Task<ResolutionResult<bool>> EnsureSshKeyPairAsync(CancellationToken cancellationToken);
}

internal sealed class SessionSshKeyPairService : ISessionSshKeyPairService
{
    public async Task<ResolutionResult<bool>> EnsureSshKeyPairAsync(CancellationToken cancellationToken)
    {
        var configDir = SessionRuntimeInfrastructure.ResolveConfigDirectory();
        Directory.CreateDirectory(configDir);

        var privateKey = SessionRuntimeInfrastructure.ResolveSshPrivateKeyPath();
        var publicKey = SessionRuntimeInfrastructure.ResolveSshPublicKeyPath();

        if (!File.Exists(privateKey) || !File.Exists(publicKey))
        {
            var keygen = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
                "ssh-keygen",
                ["-t", "ed25519", "-N", string.Empty, "-f", privateKey, "-C", "containai"],
                cancellationToken).ConfigureAwait(false);

            if (keygen.ExitCode != 0)
            {
                return ResolutionResult<bool>.ErrorResult(
                    $"Failed to generate SSH key: {SessionRuntimeInfrastructure.TrimOrFallback(keygen.StandardError, "ssh-keygen failed")}");
            }
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }
}
