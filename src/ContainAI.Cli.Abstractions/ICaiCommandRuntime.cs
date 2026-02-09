namespace ContainAI.Cli.Abstractions;

public interface ICaiCommandRuntime
{
    Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunDoctorAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunDoctorFixAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunValidateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunSetupAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunImportAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunExportAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunSyncAsync(CancellationToken cancellationToken);

    Task<int> RunStopAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunGcAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunSshAsync(CancellationToken cancellationToken);

    Task<int> RunSshCleanupAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunLinksAsync(CancellationToken cancellationToken);

    Task<int> RunLinksCheckAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunLinksFixAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunConfigAsync(CancellationToken cancellationToken);

    Task<int> RunConfigListAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunConfigGetAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunConfigSetAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunConfigUnsetAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunConfigResolveVolumeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunManifestAsync(CancellationToken cancellationToken);

    Task<int> RunManifestParseAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunManifestGenerateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunManifestApplyAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunManifestCheckAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunTemplateAsync(CancellationToken cancellationToken);

    Task<int> RunTemplateUpgradeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunUpdateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunRefreshAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunUninstallAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunHelpAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunSystemAsync(CancellationToken cancellationToken);

    Task<int> RunSystemInitAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunSystemLinkRepairAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunSystemWatchLinksAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunSystemDevcontainerAsync(CancellationToken cancellationToken);

    Task<int> RunSystemDevcontainerInstallAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken);

    Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken);

    Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken);

    Task<int> RunVersionAsync(CancellationToken cancellationToken);

    Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken);

    Task<int> RunInstallAsync(InstallCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunExamplesListAsync(CancellationToken cancellationToken);

    Task<int> RunExamplesExportAsync(ExamplesExportCommandOptions options, CancellationToken cancellationToken);
}
