namespace ContainAI.Cli.Host.Devcontainer.Configuration;

internal sealed class DevcontainerFeatureSettingsFactory : IDevcontainerFeatureSettingsFactory
{
    private readonly IDevcontainerFeatureConfigService configService;
    private readonly Func<string, string?> environmentVariableReader;

    public DevcontainerFeatureSettingsFactory(
        IDevcontainerFeatureConfigService configService,
        Func<string, string?> environmentVariableReader)
    {
        this.configService = configService ?? throw new ArgumentNullException(nameof(configService));
        this.environmentVariableReader = environmentVariableReader ?? throw new ArgumentNullException(nameof(environmentVariableReader));
    }

    public bool TryCreateFeatureConfig(out FeatureConfig settings, out string error)
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
            DataVolume: environmentVariableReader("DATAVOLUME") ?? DevcontainerFeaturePaths.DefaultDataVolume,
            EnableCredentials: enableCredentials,
            EnableSsh: enableSsh,
            InstallDocker: installDocker,
            RemoteUser: environmentVariableReader("REMOTEUSER") ?? "auto");

        if (!configService.ValidateFeatureConfig(settings, out var validationError))
        {
            error = validationError;
            return false;
        }

        error = string.Empty;
        return true;
    }
}
