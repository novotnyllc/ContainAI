using ContainAI.Cli;
using ContainAI.Cli.Abstractions;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class RootCommandRuntimeForwardingTests
{
    [Theory]
    [MemberData(nameof(RuntimeForwardingCases))]
    public async Task StaticCommands_ForwardExpectedArgs(string[] input, string[] expected)
    {
        var runtime = new RecordingRuntime();
        var exitCode = await CaiCli.RunAsync(input, runtime, TestContext.Current.CancellationToken);

        Assert.Equal(RecordingRuntime.RuntimeExitCode, exitCode);
        Assert.Collection(
            runtime.RuntimeCalls,
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

        Assert.Equal(RecordingRuntime.RuntimeExitCode, exitCode);
        Assert.Collection(
            runtime.RuntimeCalls,
            args => Assert.Equal(["import", "--from", "/tmp/source", "--dry-run"], args));
    }

    [Fact]
    public async Task Links_UsesPositionalWorkspace_WhenWorkspaceOptionNotSet()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(["links", "check", "/tmp/workspace", "--dry-run"], runtime, TestContext.Current.CancellationToken);

        Assert.Equal(RecordingRuntime.RuntimeExitCode, exitCode);
        Assert.Collection(
            runtime.RuntimeCalls,
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
        Assert.Empty(runtime.RuntimeCalls);
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
        Assert.Empty(runtime.RuntimeCalls);
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
        Assert.Empty(runtime.RuntimeCalls);
    }

    [Fact]
    public async Task DoctorFix_AllWithTarget_FailsParser()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(["doctor", "fix", "--all", "container"], runtime, TestContext.Current.CancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.RuntimeCalls);
    }

    [Fact]
    public async Task DoctorFix_InvalidTarget_FailsParser()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(["doctor", "fix", "sandbox-1"], runtime, TestContext.Current.CancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.RuntimeCalls);
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
        Assert.Empty(runtime.RuntimeCalls);
    }

    public static TheoryData<string[], string[]> RuntimeForwardingCases()
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
            { ["system", "init", "--data-dir", "/mnt/agent-data", "--home-dir", "/home/agent", "--manifests-dir", "/opt/containai/manifests", "--template-hooks", "/etc/containai/template-hooks/startup.d", "--workspace-hooks", "/home/agent/workspace/.containai/hooks/startup.d", "--workspace-dir", "/home/agent/workspace", "--quiet"], ["system", "init", "--data-dir", "/mnt/agent-data", "--home-dir", "/home/agent", "--manifests-dir", "/opt/containai/manifests", "--template-hooks", "/etc/containai/template-hooks/startup.d", "--workspace-hooks", "/home/agent/workspace/.containai/hooks/startup.d", "--workspace-dir", "/home/agent/workspace", "--quiet"] },
            { ["system", "link-repair", "--check", "--dry-run", "--quiet", "--builtin-spec", "/tmp/builtin.json", "--user-spec", "/tmp/user.json", "--checked-at-file", "/tmp/checked"], ["system", "link-repair", "--check", "--dry-run", "--quiet", "--builtin-spec", "/tmp/builtin.json", "--user-spec", "/tmp/user.json", "--checked-at-file", "/tmp/checked"] },
            { ["system", "watch-links", "--poll-interval", "30", "--imported-at-file", "/tmp/imported", "--checked-at-file", "/tmp/checked", "--quiet"], ["system", "watch-links", "--poll-interval", "30", "--imported-at-file", "/tmp/imported", "--checked-at-file", "/tmp/checked", "--quiet"] },
            { ["system", "devcontainer", "install", "--feature-dir", "/tmp/feature"], ["system", "devcontainer", "install", "--feature-dir", "/tmp/feature"] },
            { ["system", "devcontainer", "init"], ["system", "devcontainer", "init"] },
            { ["system", "devcontainer", "start"], ["system", "devcontainer", "start"] },
            { ["system", "devcontainer", "verify-sysbox"], ["system", "devcontainer", "verify-sysbox"] },
        };
    }

    private sealed class RecordingRuntime : RecordingCaiRuntimeBase
    {
        public const int RunExitCode = 11;
        public const int ShellExitCode = 12;
        public const int ExecExitCode = 13;
        public const int DockerExitCode = 14;
        public const int StatusExitCode = 15;
        public const int RuntimeExitCode = 16;
        public const int AcpExitCode = 17;
        public const int InstallExitCode = 18;
        public const int ExamplesListExitCode = 19;
        public const int ExamplesExportExitCode = 20;

        public RecordingRuntime()
            : base(
                new CaiRuntimeExitCodes(
                    RunExitCode,
                    ShellExitCode,
                    ExecExitCode,
                    DockerExitCode,
                    StatusExitCode,
                    RuntimeExitCode,
                    AcpExitCode,
                    InstallExitCode,
                    ExamplesListExitCode,
                    ExamplesExportExitCode))
        {
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
