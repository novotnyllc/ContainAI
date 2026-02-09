namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private bool TryCreateFeatureConfig(out FeatureConfig settings, out string error)
    {
        if (!configService.TryParseFeatureBoolean("ENABLECREDENTIALS", defaultValue: false, out var enableCredentials, out var enableCredentialsError))
        {
            settings = default!;
            error = enableCredentialsError;
            return false;
        }

        if (!configService.TryParseFeatureBoolean("ENABLESSH", defaultValue: true, out var enableSsh, out var enableSshError))
        {
            settings = default!;
            error = enableSshError;
            return false;
        }

        if (!configService.TryParseFeatureBoolean("INSTALLDOCKER", defaultValue: true, out var installDocker, out var installDockerError))
        {
            settings = default!;
            error = installDockerError;
            return false;
        }

        settings = new FeatureConfig(
            DataVolume: Environment.GetEnvironmentVariable("DATAVOLUME") ?? DefaultDataVolume,
            EnableCredentials: enableCredentials,
            EnableSsh: enableSsh,
            InstallDocker: installDocker,
            RemoteUser: Environment.GetEnvironmentVariable("REMOTEUSER") ?? "auto");

        if (!configService.ValidateFeatureConfig(settings, out var validationError))
        {
            error = validationError;
            return false;
        }

        error = string.Empty;
        return true;
    }
}
