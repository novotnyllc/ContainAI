using ContainAI.Cli;
using ContainAI.Cli.Abstractions;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class RootCommandNativeForwardingTests
{
    [Theory]
    [MemberData(nameof(NativeForwardingCases))]
    public async Task StaticCommands_ForwardExpectedArgs(string[] input, string[] expected)
    {
        var runtime = new RecordingRuntime();
        var exitCode = await CaiCli.RunAsync(input, runtime, TestContext.Current.CancellationToken);

        Assert.Equal(RecordingRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            args => Assert.Equal(expected, args));
    }

    [Fact]
    public async Task Run_UsesPositionalWorkspacePath_WhenDirectoryExists()
    {
        var runtime = new RecordingRuntime();
        using var temp = new TempDirectory();

        var exitCode = await CaiCli.RunAsync(["run", temp.Path], runtime, TestContext.Current.CancellationToken);

        Assert.Equal(RecordingRuntime.RunExitCode, exitCode);
        Assert.Single(runtime.RunCalls);
        Assert.Equal(temp.Path, runtime.RunCalls[0].Workspace);
        Assert.Empty(runtime.RunCalls[0].CommandArgs);
    }

    [Fact]
    public async Task Run_UsesPositionalTokenAsCommand_WhenDirectoryDoesNotExist()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(["run", "echo", "hello"], runtime, TestContext.Current.CancellationToken);

        Assert.Equal(RecordingRuntime.RunExitCode, exitCode);
        Assert.Single(runtime.RunCalls);
        Assert.Null(runtime.RunCalls[0].Workspace);
        Assert.Equal(["echo", "hello"], runtime.RunCalls[0].CommandArgs);
    }

    [Fact]
    public async Task Shell_UsesPositionalWorkspacePath()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(["shell", "/tmp/workspace"], runtime, TestContext.Current.CancellationToken);

        Assert.Equal(RecordingRuntime.ShellExitCode, exitCode);
        Assert.Single(runtime.ShellCalls);
        Assert.Equal("/tmp/workspace", runtime.ShellCalls[0].Workspace);
    }

    [Fact]
    public async Task Import_UsesPositionalSourcePath_WhenFromNotSet()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(["import", "/tmp/source", "--dry-run"], runtime, TestContext.Current.CancellationToken);

        Assert.Equal(RecordingRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            args => Assert.Equal(["import", "--from", "/tmp/source", "--dry-run"], args));
    }

    [Fact]
    public async Task Links_UsesPositionalWorkspace_WhenWorkspaceOptionNotSet()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(["links", "check", "/tmp/workspace", "--dry-run"], runtime, TestContext.Current.CancellationToken);

        Assert.Equal(RecordingRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            args => Assert.Equal(["links", "check", "--workspace", "/tmp/workspace", "--dry-run"], args));
    }

    [Fact]
    public async Task Install_UsesTypedInstallRuntime()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(
            ["install", "--local", "--yes", "--no-setup", "--install-dir", "/tmp/install", "--bin-dir", "/tmp/bin", "--channel", "stable", "--verbose"],
            runtime,
            TestContext.Current.CancellationToken);

        Assert.Equal(RecordingRuntime.InstallExitCode, exitCode);
        Assert.Empty(runtime.NativeCalls);
        Assert.Collection(
            runtime.InstallCalls,
            options =>
            {
                Assert.True(options.Local);
                Assert.True(options.Yes);
                Assert.True(options.NoSetup);
                Assert.True(options.Verbose);
                Assert.Equal("/tmp/install", options.InstallDir);
                Assert.Equal("/tmp/bin", options.BinDir);
                Assert.Equal("stable", options.Channel);
            });
    }

    [Fact]
    public async Task Examples_UsesTypedExamplesRuntime()
    {
        var runtime = new RecordingRuntime();

        var listExitCode = await CaiCli.RunAsync(["examples"], runtime, TestContext.Current.CancellationToken);
        var exportExitCode = await CaiCli.RunAsync(["examples", "export", "--output-dir", "/tmp/examples", "--force"], runtime, TestContext.Current.CancellationToken);

        Assert.Equal(RecordingRuntime.ExamplesListExitCode, listExitCode);
        Assert.Equal(RecordingRuntime.ExamplesExportExitCode, exportExitCode);
        Assert.Empty(runtime.NativeCalls);
        Assert.Equal(1, runtime.ExamplesListCalls);
        Assert.Collection(
            runtime.ExamplesExportCalls,
            options =>
            {
                Assert.Equal("/tmp/examples", options.OutputDir);
                Assert.True(options.Force);
            });
    }

    [Fact]
    public async Task ManifestGenerate_InvalidKind_FailsParser()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(["manifest", "generate", "invalid", "src/manifests"], runtime, TestContext.Current.CancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task DoctorFix_AllWithTarget_FailsParser()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(["doctor", "fix", "--all", "container"], runtime, TestContext.Current.CancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task DoctorFix_InvalidTarget_FailsParser()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(["doctor", "fix", "sandbox-1"], runtime, TestContext.Current.CancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task ManifestCheck_WithOptionAndPositionalDirectory_FailsParser()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(
            ["manifest", "check", "--manifest-dir", "src/manifests", "src/manifests"],
            runtime,
            TestContext.Current.CancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.NativeCalls);
    }

    public static TheoryData<string[], string[]> NativeForwardingCases()
    {
        return new TheoryData<string[], string[]>
        {
            { ["doctor", "--json", "--build-templates", "--reset-lima"], ["doctor", "--json", "--build-templates", "--reset-lima"] },
            { ["doctor", "fix", "--all", "--dry-run"], ["doctor", "fix", "--all", "--dry-run"] },
            { ["doctor", "fix", "container", "sandbox-1"], ["doctor", "fix", "container", "sandbox-1"] },
            { ["validate", "--json"], ["validate", "--json"] },
            { ["setup", "--dry-run", "--verbose", "--skip-templates"], ["setup", "--dry-run", "--verbose", "--skip-templates"] },
            { ["export", "--output", "/tmp/out.tgz", "--container", "demo"], ["export", "--output", "/tmp/out.tgz", "--container", "demo"] },
            { ["sync"], ["sync"] },
            { ["stop", "--all", "--remove", "--force", "--export", "--verbose"], ["stop", "--all", "--remove", "--force", "--export", "--verbose"] },
            { ["gc", "--dry-run", "--force", "--images", "--age", "7d"], ["gc", "--dry-run", "--force", "--images", "--age", "7d"] },
            { ["ssh", "cleanup", "--dry-run"], ["ssh", "cleanup", "--dry-run"] },
            { ["links", "fix", "--workspace", "/tmp/ws", "--dry-run", "--quiet"], ["links", "fix", "--workspace", "/tmp/ws", "--dry-run", "--quiet"] },
            { ["config", "--global", "--workspace", "/tmp/ws", "--verbose", "set", "agent.default", "claude"], ["config", "--global", "--workspace", "/tmp/ws", "--verbose", "set", "agent.default", "claude"] },
            { ["manifest", "parse", "--include-disabled", "--emit-source-file", "src/manifests"], ["manifest", "parse", "--include-disabled", "--emit-source-file", "src/manifests"] },
            { ["manifest", "generate", "container-link-spec", "src/manifests", "/tmp/links.json"], ["manifest", "generate", "container-link-spec", "src/manifests", "/tmp/links.json"] },
            { ["manifest", "apply", "init-dirs", "src/manifests", "--data-dir", "/tmp/data", "--home-dir", "/tmp/home"], ["manifest", "apply", "init-dirs", "src/manifests", "--data-dir", "/tmp/data", "--home-dir", "/tmp/home"] },
            { ["manifest", "apply", "agent-shims", "src/manifests", "--shim-dir", "/tmp/shims", "--cai-binary", "/usr/local/bin/cai"], ["manifest", "apply", "agent-shims", "src/manifests", "--shim-dir", "/tmp/shims", "--cai-binary", "/usr/local/bin/cai"] },
            { ["manifest", "check", "--manifest-dir", "src/manifests"], ["manifest", "check", "--manifest-dir", "src/manifests"] },
            { ["template", "upgrade", "default", "--dry-run"], ["template", "upgrade", "default", "--dry-run"] },
            { ["update", "--dry-run", "--stop-containers", "--force", "--lima-recreate", "--verbose"], ["update", "--dry-run", "--stop-containers", "--force", "--lima-recreate", "--verbose"] },
            { ["refresh", "--rebuild", "--verbose"], ["refresh", "--rebuild", "--verbose"] },
            { ["uninstall", "--dry-run", "--containers", "--volumes", "--force", "--verbose"], ["uninstall", "--dry-run", "--containers", "--volumes", "--force", "--verbose"] },
            { ["help", "config"], ["help", "config"] },
            { ["system", "init", "--data-dir", "/mnt/agent-data", "--home-dir", "/home/agent", "--manifests-dir", "/opt/containai/manifests", "--template-hooks", "/etc/containai/template-hooks/startup.d", "--workspace-hooks", "/home/agent/workspace/.containai/hooks/startup.d", "--workspace-dir", "/home/agent/workspace", "--quiet"], ["system", "init", "--data-dir", "/mnt/agent-data", "--home-dir", "/home/agent", "--manifests-dir", "/opt/containai/manifests", "--template-hooks", "/etc/containai/template-hooks/startup.d", "--workspace-hooks", "/home/agent/workspace/.containai/hooks/startup.d", "--workspace-dir", "/home/agent/workspace", "--quiet"] },
            { ["system", "link-repair", "--check", "--dry-run", "--quiet", "--builtin-spec", "/tmp/builtin.json", "--user-spec", "/tmp/user.json", "--checked-at-file", "/tmp/checked"], ["system", "link-repair", "--check", "--dry-run", "--quiet", "--builtin-spec", "/tmp/builtin.json", "--user-spec", "/tmp/user.json", "--checked-at-file", "/tmp/checked"] },
            { ["system", "watch-links", "--poll-interval", "30", "--imported-at-file", "/tmp/imported", "--checked-at-file", "/tmp/checked", "--quiet"], ["system", "watch-links", "--poll-interval", "30", "--imported-at-file", "/tmp/imported", "--checked-at-file", "/tmp/checked", "--quiet"] },
            { ["system", "devcontainer", "install", "--feature-dir", "/tmp/feature"], ["system", "devcontainer", "install", "--feature-dir", "/tmp/feature"] },
            { ["system", "devcontainer", "init"], ["system", "devcontainer", "init"] },
            { ["system", "devcontainer", "start"], ["system", "devcontainer", "start"] },
            { ["system", "devcontainer", "verify-sysbox"], ["system", "devcontainer", "verify-sysbox"] },
        };
    }

    private sealed class RecordingRuntime : ICaiCommandRuntime
    {
        public const int RunExitCode = 11;
        public const int ShellExitCode = 12;
        public const int ExecExitCode = 13;
        public const int DockerExitCode = 14;
        public const int StatusExitCode = 15;
        public const int NativeExitCode = 16;
        public const int AcpExitCode = 17;
        public const int InstallExitCode = 18;
        public const int ExamplesListExitCode = 19;
        public const int ExamplesExportExitCode = 20;

        public List<RunCommandOptions> RunCalls { get; } = [];

        public List<ShellCommandOptions> ShellCalls { get; } = [];

        public List<ExecCommandOptions> ExecCalls { get; } = [];

        public List<DockerCommandOptions> DockerCalls { get; } = [];

        public List<StatusCommandOptions> StatusCalls { get; } = [];

        public List<IReadOnlyList<string>> NativeCalls { get; } = [];

        public List<string> AcpCalls { get; } = [];
        public List<InstallCommandOptions> InstallCalls { get; } = [];
        public int ExamplesListCalls { get; private set; }
        public List<ExamplesExportCommandOptions> ExamplesExportCalls { get; } = [];

        public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
        {
            RunCalls.Add(options);
            return Task.FromResult(RunExitCode);
        }

        public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
        {
            ShellCalls.Add(options);
            return Task.FromResult(ShellExitCode);
        }

        public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
        {
            ExecCalls.Add(options);
            return Task.FromResult(ExecExitCode);
        }

        public Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
        {
            DockerCalls.Add(options);
            return Task.FromResult(DockerExitCode);
        }

        public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
        {
            StatusCalls.Add(options);
            return Task.FromResult(StatusExitCode);
        }

        public Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--json", options.Json);
            AppendFlag(args, "--build-templates", options.BuildTemplates);
            AppendFlag(args, "--reset-lima", options.ResetLima);
            return RecordNativeCall(["doctor"], args);
        }

        public Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--all", options.All);
            AppendFlag(args, "--dry-run", options.DryRun);
            AppendArgument(args, options.Target);
            AppendArgument(args, options.TargetArg);
            return RecordNativeCall(["doctor", "fix"], args);
        }

        public Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--json", options.Json);
            return RecordNativeCall(["validate"], args);
        }

        public Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--dry-run", options.DryRun);
            AppendFlag(args, "--verbose", options.Verbose);
            AppendFlag(args, "--skip-templates", options.SkipTemplates);
            return RecordNativeCall(["setup"], args);
        }

        public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendOption(args, "--from", options.From);
            AppendOption(args, "--data-volume", options.DataVolume);
            AppendOption(args, "--workspace", options.Workspace);
            AppendOption(args, "--config", options.Config);
            AppendFlag(args, "--dry-run", options.DryRun);
            AppendFlag(args, "--no-excludes", options.NoExcludes);
            AppendFlag(args, "--no-secrets", options.NoSecrets);
            AppendFlag(args, "--verbose", options.Verbose);
            return RecordNativeCall(["import"], args);
        }

        public Task<int> RunExportAsync(ExportCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendOption(args, "--output", options.Output);
            AppendOption(args, "--data-volume", options.DataVolume);
            AppendOption(args, "--container", options.Container);
            AppendOption(args, "--workspace", options.Workspace);
            return RecordNativeCall(["export"], args);
        }

        public Task<int> RunSyncAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["sync"]);

        public Task<int> RunStopAsync(StopCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--all", options.All);
            AppendOption(args, "--container", options.Container);
            AppendFlag(args, "--remove", options.Remove);
            AppendFlag(args, "--force", options.Force);
            AppendFlag(args, "--export", options.Export);
            AppendFlag(args, "--verbose", options.Verbose);
            return RecordNativeCall(["stop"], args);
        }

        public Task<int> RunGcAsync(GcCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--dry-run", options.DryRun);
            AppendFlag(args, "--force", options.Force);
            AppendFlag(args, "--images", options.Images);
            AppendOption(args, "--age", options.Age);
            return RecordNativeCall(["gc"], args);
        }

        public Task<int> RunSshAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["ssh"]);

        public Task<int> RunSshCleanupAsync(SshCleanupCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--dry-run", options.DryRun);
            return RecordNativeCall(["ssh", "cleanup"], args);
        }

        public Task<int> RunLinksAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["links"]);

        public Task<int> RunLinksCheckAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendOption(args, "--name", options.Name);
            AppendOption(args, "--container", options.Container);
            AppendOption(args, "--workspace", options.Workspace);
            AppendFlag(args, "--dry-run", options.DryRun);
            AppendFlag(args, "--quiet", options.Quiet);
            AppendFlag(args, "--verbose", options.Verbose);
            AppendOption(args, "--config", options.Config);
            return RecordNativeCall(["links", "check"], args);
        }

        public Task<int> RunLinksFixAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendOption(args, "--name", options.Name);
            AppendOption(args, "--container", options.Container);
            AppendOption(args, "--workspace", options.Workspace);
            AppendFlag(args, "--dry-run", options.DryRun);
            AppendFlag(args, "--quiet", options.Quiet);
            AppendFlag(args, "--verbose", options.Verbose);
            AppendOption(args, "--config", options.Config);
            return RecordNativeCall(["links", "fix"], args);
        }

        public Task<int> RunConfigAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["config"]);

        public Task<int> RunConfigListAsync(ConfigListCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--global", options.Global);
            AppendOption(args, "--workspace", options.Workspace);
            AppendFlag(args, "--verbose", options.Verbose);
            args.Add("list");
            return RecordNativeCall(["config"], args);
        }

        public Task<int> RunConfigGetAsync(ConfigGetCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--global", options.Global);
            AppendOption(args, "--workspace", options.Workspace);
            AppendFlag(args, "--verbose", options.Verbose);
            args.Add("get");
            args.Add(options.Key);
            return RecordNativeCall(["config"], args);
        }

        public Task<int> RunConfigSetAsync(ConfigSetCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--global", options.Global);
            AppendOption(args, "--workspace", options.Workspace);
            AppendFlag(args, "--verbose", options.Verbose);
            args.Add("set");
            args.Add(options.Key);
            args.Add(options.Value);
            return RecordNativeCall(["config"], args);
        }

        public Task<int> RunConfigUnsetAsync(ConfigUnsetCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--global", options.Global);
            AppendOption(args, "--workspace", options.Workspace);
            AppendFlag(args, "--verbose", options.Verbose);
            args.Add("unset");
            args.Add(options.Key);
            return RecordNativeCall(["config"], args);
        }

        public Task<int> RunConfigResolveVolumeAsync(ConfigResolveVolumeCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--global", options.Global);
            AppendOption(args, "--workspace", options.Workspace);
            AppendFlag(args, "--verbose", options.Verbose);
            args.Add("resolve-volume");
            AppendArgument(args, options.ExplicitVolume);
            return RecordNativeCall(["config"], args);
        }

        public Task<int> RunManifestAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["manifest"]);

        public Task<int> RunManifestParseAsync(ManifestParseCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--include-disabled", options.IncludeDisabled);
            AppendFlag(args, "--emit-source-file", options.EmitSourceFile);
            args.Add(options.ManifestPath);
            return RecordNativeCall(["manifest", "parse"], args);
        }

        public Task<int> RunManifestGenerateAsync(ManifestGenerateCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>
            {
                options.Kind,
                options.ManifestPath,
            };
            AppendArgument(args, options.OutputPath);
            return RecordNativeCall(["manifest", "generate"], args);
        }

        public Task<int> RunManifestApplyAsync(ManifestApplyCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>
            {
                options.Kind,
                options.ManifestPath,
            };
            AppendOption(args, "--data-dir", options.DataDir);
            AppendOption(args, "--home-dir", options.HomeDir);
            AppendOption(args, "--shim-dir", options.ShimDir);
            AppendOption(args, "--cai-binary", options.CaiBinary);
            return RecordNativeCall(["manifest", "apply"], args);
        }

        public Task<int> RunManifestCheckAsync(ManifestCheckCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendOption(args, "--manifest-dir", options.ManifestDir);
            return RecordNativeCall(["manifest", "check"], args);
        }

        public Task<int> RunTemplateAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["template"]);

        public Task<int> RunTemplateUpgradeAsync(TemplateUpgradeCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendArgument(args, options.Name);
            AppendFlag(args, "--dry-run", options.DryRun);
            return RecordNativeCall(["template", "upgrade"], args);
        }

        public Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--dry-run", options.DryRun);
            AppendFlag(args, "--stop-containers", options.StopContainers);
            AppendFlag(args, "--force", options.Force);
            AppendFlag(args, "--lima-recreate", options.LimaRecreate);
            AppendFlag(args, "--verbose", options.Verbose);
            return RecordNativeCall(["update"], args);
        }

        public Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--rebuild", options.Rebuild);
            AppendFlag(args, "--verbose", options.Verbose);
            return RecordNativeCall(["refresh"], args);
        }

        public Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--dry-run", options.DryRun);
            AppendFlag(args, "--containers", options.Containers);
            AppendFlag(args, "--volumes", options.Volumes);
            AppendFlag(args, "--force", options.Force);
            AppendFlag(args, "--verbose", options.Verbose);
            return RecordNativeCall(["uninstall"], args);
        }

        public Task<int> RunHelpAsync(HelpCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendArgument(args, options.Topic);
            return RecordNativeCall(["help"], args);
        }

        public Task<int> RunSystemAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["system"]);

        public Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendOption(args, "--data-dir", options.DataDir);
            AppendOption(args, "--home-dir", options.HomeDir);
            AppendOption(args, "--manifests-dir", options.ManifestsDir);
            AppendOption(args, "--template-hooks", options.TemplateHooks);
            AppendOption(args, "--workspace-hooks", options.WorkspaceHooks);
            AppendOption(args, "--workspace-dir", options.WorkspaceDir);
            AppendFlag(args, "--quiet", options.Quiet);
            return RecordNativeCall(["system", "init"], args);
        }

        public Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendFlag(args, "--check", options.Check);
            AppendFlag(args, "--fix", options.Fix);
            AppendFlag(args, "--dry-run", options.DryRun);
            AppendFlag(args, "--quiet", options.Quiet);
            AppendOption(args, "--builtin-spec", options.BuiltinSpec);
            AppendOption(args, "--user-spec", options.UserSpec);
            AppendOption(args, "--checked-at-file", options.CheckedAtFile);
            return RecordNativeCall(["system", "link-repair"], args);
        }

        public Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendOption(args, "--poll-interval", options.PollInterval);
            AppendOption(args, "--imported-at-file", options.ImportedAtFile);
            AppendOption(args, "--checked-at-file", options.CheckedAtFile);
            AppendFlag(args, "--quiet", options.Quiet);
            return RecordNativeCall(["system", "watch-links"], args);
        }

        public Task<int> RunSystemDevcontainerAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["system", "devcontainer"]);

        public Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
        {
            var args = new List<string>();
            AppendOption(args, "--feature-dir", options.FeatureDir);
            return RecordNativeCall(["system", "devcontainer", "install"], args);
        }

        public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["system", "devcontainer", "init"]);

        public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["system", "devcontainer", "start"]);

        public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["system", "devcontainer", "verify-sysbox"]);

        public Task<int> RunVersionAsync(CancellationToken cancellationToken)
            => RecordNativeCall(["version"]);

        public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        {
            AcpCalls.Add(agent);
            return Task.FromResult(AcpExitCode);
        }

        public Task<int> RunInstallAsync(InstallCommandOptions options, CancellationToken cancellationToken)
        {
            InstallCalls.Add(options);
            return Task.FromResult(InstallExitCode);
        }

        public Task<int> RunExamplesListAsync(CancellationToken cancellationToken)
        {
            ExamplesListCalls++;
            return Task.FromResult(ExamplesListExitCode);
        }

        public Task<int> RunExamplesExportAsync(ExamplesExportCommandOptions options, CancellationToken cancellationToken)
        {
            ExamplesExportCalls.Add(options);
            return Task.FromResult(ExamplesExportExitCode);
        }

        private Task<int> RecordNativeCall(IReadOnlyList<string> args)
        {
            NativeCalls.Add(args.ToArray());
            return Task.FromResult(NativeExitCode);
        }

        private Task<int> RecordNativeCall(IReadOnlyList<string> commandPath, List<string> args)
        {
            return args.Count == 0
                ? RecordNativeCall(commandPath)
                : RecordNativeCall([.. commandPath, .. args]);
        }

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

    private sealed class TempDirectory : IDisposable
    {
        public TempDirectory()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"containai-static-forwarding-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            Directory.Delete(Path, recursive: true);
        }
    }
}
