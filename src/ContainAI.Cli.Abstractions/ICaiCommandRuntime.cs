namespace ContainAI.Cli.Abstractions;

public interface ICaiCommandRuntime
{
    Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunDoctorAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>();
        AppendFlag(args, "--json", options.Json);
        AppendFlag(args, "--build-templates", options.BuildTemplates);
        AppendFlag(args, "--reset-lima", options.ResetLima);
        return RunDoctorAsync(args, cancellationToken);
    }

    Task<int> RunDoctorFixAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>();
        AppendFlag(args, "--all", options.All);
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendArgument(args, options.Target);
        AppendArgument(args, options.TargetArg);
        return RunDoctorFixAsync(args, cancellationToken);
    }

    Task<int> RunValidateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>();
        AppendFlag(args, "--json", options.Json);
        return RunValidateAsync(args, cancellationToken);
    }

    Task<int> RunSetupAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>();
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--verbose", options.Verbose);
        AppendFlag(args, "--skip-templates", options.SkipTemplates);
        return RunSetupAsync(args, cancellationToken);
    }

    Task<int> RunImportAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>();
        AppendOption(args, "--from", options.From);
        AppendOption(args, "--data-volume", options.DataVolume);
        AppendOption(args, "--workspace", options.Workspace);
        AppendOption(args, "--config", options.Config);
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--no-excludes", options.NoExcludes);
        AppendFlag(args, "--no-secrets", options.NoSecrets);
        AppendFlag(args, "--verbose", options.Verbose);
        return RunImportAsync(args, cancellationToken);
    }

    Task<int> RunExportAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunExportAsync(ExportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>();
        AppendOption(args, "--output", options.Output);
        AppendOption(args, "--data-volume", options.DataVolume);
        AppendOption(args, "--container", options.Container);
        AppendOption(args, "--workspace", options.Workspace);
        return RunExportAsync(args, cancellationToken);
    }

    Task<int> RunSyncAsync(CancellationToken cancellationToken);

    Task<int> RunStopAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunStopAsync(StopCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>();
        AppendFlag(args, "--all", options.All);
        AppendOption(args, "--container", options.Container);
        AppendFlag(args, "--remove", options.Remove);
        AppendFlag(args, "--force", options.Force);
        AppendFlag(args, "--export", options.Export);
        AppendFlag(args, "--verbose", options.Verbose);
        return RunStopAsync(args, cancellationToken);
    }

    Task<int> RunGcAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunGcAsync(GcCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>();
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--force", options.Force);
        AppendFlag(args, "--images", options.Images);
        AppendOption(args, "--age", options.Age);
        return RunGcAsync(args, cancellationToken);
    }

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

    Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>();
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--stop-containers", options.StopContainers);
        AppendFlag(args, "--force", options.Force);
        AppendFlag(args, "--lima-recreate", options.LimaRecreate);
        AppendFlag(args, "--verbose", options.Verbose);
        return RunUpdateAsync(args, cancellationToken);
    }

    Task<int> RunRefreshAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>();
        AppendFlag(args, "--rebuild", options.Rebuild);
        AppendFlag(args, "--verbose", options.Verbose);
        return RunRefreshAsync(args, cancellationToken);
    }

    Task<int> RunUninstallAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var args = new List<string>();
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--containers", options.Containers);
        AppendFlag(args, "--volumes", options.Volumes);
        AppendFlag(args, "--force", options.Force);
        AppendFlag(args, "--verbose", options.Verbose);
        return RunUninstallAsync(args, cancellationToken);
    }

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

    private static void AppendFlag(List<string> args, string option, bool enabled)
    {
        if (enabled)
        {
            args.Add(option);
        }
    }

    private static void AppendOption(List<string> args, string option, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            args.Add(option);
            args.Add(value);
        }
    }

    private static void AppendArgument(List<string> args, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            args.Add(value);
        }
    }
}
