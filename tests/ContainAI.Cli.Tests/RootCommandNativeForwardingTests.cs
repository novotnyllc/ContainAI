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
    public async Task ManifestGenerate_InvalidKind_FailsParser()
    {
        var runtime = new RecordingRuntime();

        var exitCode = await CaiCli.RunAsync(["manifest", "generate", "invalid", "src/manifests"], runtime, TestContext.Current.CancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.NativeCalls);
    }

    public static TheoryData<string[], string[]> NativeForwardingCases()
    {
        return new TheoryData<string[], string[]>
        {
            { ["doctor", "--json", "--build-templates", "--reset-lima"], ["doctor", "--json", "--build-templates", "--reset-lima"] },
            { ["doctor", "fix", "--all", "--dry-run", "container"], ["doctor", "fix", "--all", "--dry-run", "container"] },
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
            { ["manifest", "generate", "import-map", "src/manifests", "/tmp/map.sh"], ["manifest", "generate", "import-map", "src/manifests", "/tmp/map.sh"] },
            { ["manifest", "apply", "init-dirs", "src/manifests", "--data-dir", "/tmp/data", "--home-dir", "/tmp/home"], ["manifest", "apply", "init-dirs", "src/manifests", "--data-dir", "/tmp/data", "--home-dir", "/tmp/home"] },
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

        public List<RunCommandOptions> RunCalls { get; } = [];

        public List<ShellCommandOptions> ShellCalls { get; } = [];

        public List<ExecCommandOptions> ExecCalls { get; } = [];

        public List<DockerCommandOptions> DockerCalls { get; } = [];

        public List<StatusCommandOptions> StatusCalls { get; } = [];

        public List<IReadOnlyList<string>> NativeCalls { get; } = [];

        public List<string> AcpCalls { get; } = [];

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

        public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        {
            AcpCalls.Add(agent);
            return Task.FromResult(AcpExitCode);
        }

        public Task<int> RunNativeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        {
            NativeCalls.Add(args.ToArray());
            return Task.FromResult(NativeExitCode);
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
