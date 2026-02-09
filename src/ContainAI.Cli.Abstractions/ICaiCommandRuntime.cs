namespace ContainAI.Cli.Abstractions;

public interface ICaiCommandRuntime
{
    Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunExportAsync(ExportCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunSyncAsync(CancellationToken cancellationToken);

    Task<int> RunStopAsync(StopCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunGcAsync(GcCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunSshAsync(CancellationToken cancellationToken);

    Task<int> RunSshCleanupAsync(SshCleanupCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunLinksAsync(CancellationToken cancellationToken);

    Task<int> RunLinksCheckAsync(LinksSubcommandOptions options, CancellationToken cancellationToken);

    Task<int> RunLinksFixAsync(LinksSubcommandOptions options, CancellationToken cancellationToken);

    Task<int> RunConfigAsync(CancellationToken cancellationToken);

    Task<int> RunConfigListAsync(ConfigListCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunConfigGetAsync(ConfigGetCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunConfigSetAsync(ConfigSetCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunConfigUnsetAsync(ConfigUnsetCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunConfigResolveVolumeAsync(ConfigResolveVolumeCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunManifestAsync(CancellationToken cancellationToken);

    Task<int> RunManifestParseAsync(ManifestParseCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunManifestGenerateAsync(ManifestGenerateCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunManifestApplyAsync(ManifestApplyCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunManifestCheckAsync(ManifestCheckCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunTemplateAsync(CancellationToken cancellationToken);

    Task<int> RunTemplateUpgradeAsync(TemplateUpgradeCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunHelpAsync(HelpCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunSystemAsync(CancellationToken cancellationToken);

    Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunSystemDevcontainerAsync(CancellationToken cancellationToken);

    Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken);

    Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken);

    Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken);

    Task<int> RunVersionAsync(CancellationToken cancellationToken);

    Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken);

    Task<int> RunInstallAsync(InstallCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunExamplesListAsync(CancellationToken cancellationToken);

    Task<int> RunExamplesExportAsync(ExamplesExportCommandOptions options, CancellationToken cancellationToken);
}
