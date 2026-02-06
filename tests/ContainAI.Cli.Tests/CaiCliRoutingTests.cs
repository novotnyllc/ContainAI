using System.Text.Json;
using ContainAI.Cli;
using ContainAI.Cli.Abstractions;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class CaiCliRoutingTests
{
    [Fact]
    public async Task NoArgs_UsesNativeRunRuntime_DefaultRun()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync([], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.RunExitCode, exitCode);
        Assert.Single(runtime.RunCalls);
        Assert.Empty(runtime.RunCalls[0].AdditionalArgs);
        Assert.Empty(runtime.RunCalls[0].CommandArgs);
    }

    [Fact]
    public async Task RunCommand_UsesNativeRunRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["run", "--fresh", "--detached", "echo", "ok"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.RunExitCode, exitCode);
        Assert.Single(runtime.RunCalls);
        Assert.True(runtime.RunCalls[0].Fresh);
        Assert.True(runtime.RunCalls[0].Detached);
        Assert.Equal(["echo", "ok"], runtime.RunCalls[0].CommandArgs);
    }

    [Fact]
    public async Task ShellCommand_UsesNativeShellRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["shell", "--workspace", "/tmp/workspace"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.ShellExitCode, exitCode);
        Assert.Single(runtime.ShellCalls);
        Assert.Equal("/tmp/workspace", runtime.ShellCalls[0].Workspace);
    }

    [Fact]
    public async Task ExecCommand_UsesNativeExecRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["exec", "ssh-target", "echo", "hi"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.ExecExitCode, exitCode);
        Assert.Single(runtime.ExecCalls);
        Assert.Equal(["ssh-target", "echo", "hi"], runtime.ExecCalls[0].CommandArgs);
    }

    [Fact]
    public async Task DockerCommand_UsesNativeDockerRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["docker", "ps", "-a"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.DockerExitCode, exitCode);
        Assert.Single(runtime.DockerCalls);
        Assert.Equal(["ps", "-a"], runtime.DockerCalls[0].DockerArgs);
    }

    [Fact]
    public async Task StatusCommand_UsesNativeStatusRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["status", "--json", "--container", "demo"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.StatusExitCode, exitCode);
        Assert.Single(runtime.StatusCalls);
        Assert.True(runtime.StatusCalls[0].Json);
        Assert.Equal("demo", runtime.StatusCalls[0].Container);
    }

    [Fact]
    public async Task KnownLegacyCommand_UnknownSubcommand_IsForwardedToLegacyRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["config", "mystery-subcommand", "--json"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.LegacyExitCode, exitCode);
        Assert.Collection(
            runtime.LegacyCalls,
            call => Assert.Equal(["config", "mystery-subcommand", "--json"], call));
    }

    [Fact]
    public async Task UnknownFirstToken_FallsBackToLegacyRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["mystery", "token"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.LegacyExitCode, exitCode);
        Assert.Collection(
            runtime.LegacyCalls,
            call => Assert.Equal(["mystery", "token"], call));
    }

    [Fact]
    public async Task FlagFirstToken_FallsBackToLegacyRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--fresh", "/tmp/workspace"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.LegacyExitCode, exitCode);
        Assert.Collection(
            runtime.LegacyCalls,
            call => Assert.Equal(["--fresh", "/tmp/workspace"], call));
    }

    [Fact]
    public async Task AcpProxy_Subcommand_UsesAcpRuntime_WithExplicitAgent()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["acp", "proxy", "gemini"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.AcpExitCode, exitCode);
        Assert.Equal(["gemini"], runtime.AcpCalls);
        Assert.Empty(runtime.LegacyCalls);
    }

    [Fact]
    public async Task AcpProxy_Subcommand_DefaultsAgentToClaude()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["acp", "proxy"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.AcpExitCode, exitCode);
        Assert.Equal(["claude"], runtime.AcpCalls);
        Assert.Empty(runtime.LegacyCalls);
    }

    [Fact]
    public async Task LegacyAcpFlag_IsMappedToAcpRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--acp", "claude"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.AcpExitCode, exitCode);
        Assert.Equal(["claude"], runtime.AcpCalls);
        Assert.Empty(runtime.LegacyCalls);
    }

    [Fact]
    public async Task LegacyAcpFlag_WithoutAgent_DefaultsToClaude()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--acp"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.AcpExitCode, exitCode);
        Assert.Equal(["claude"], runtime.AcpCalls);
        Assert.Empty(runtime.LegacyCalls);
    }

    [Fact]
    public async Task LegacyAcpFlag_WithHelp_IsHandledByParserWithoutRuntimeInvocation()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--acp", "--help"], runtime, cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Empty(runtime.AcpCalls);
        Assert.Empty(runtime.LegacyCalls);
    }

    [Fact]
    public async Task AcpCommand_UnknownSubcommand_ReturnsErrorWithoutInvokingRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["acp", "mystery-subcommand"], runtime, cancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.AcpCalls);
        Assert.Empty(runtime.LegacyCalls);
    }

    [Fact]
    public async Task AcpProxy_WithAdditionalArgument_InvokesRuntimeWithAgent()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["acp", "proxy", "claude", "extra"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.AcpExitCode, exitCode);
        Assert.Equal(["claude"], runtime.AcpCalls);
        Assert.Empty(runtime.LegacyCalls);
    }

    [Fact]
    public async Task RefreshAlias_IsNormalizedToRefreshSubcommand()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--refresh", "--rebuild"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.LegacyExitCode, exitCode);
        Assert.Collection(
            runtime.LegacyCalls,
            call => Assert.Equal(["refresh", "--rebuild"], call));
    }

    [Fact]
    public async Task RefreshAlias_WithoutOptions_IsNormalizedToRefreshSubcommand()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--refresh"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.LegacyExitCode, exitCode);
        Assert.Collection(
            runtime.LegacyCalls,
            call => Assert.Equal(["refresh"], call));
    }

    [Fact]
    public async Task HelpSubcommand_UsesLegacyRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["help"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.LegacyExitCode, exitCode);
        Assert.Collection(
            runtime.LegacyCalls,
            call => Assert.Equal(["help"], call));
        Assert.Empty(runtime.AcpCalls);
    }

    [Fact]
    public async Task VersionSubcommand_UsesLegacyRuntime_WhenJsonNotRequested()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["version"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.LegacyExitCode, exitCode);
        Assert.Collection(
            runtime.LegacyCalls,
            call => Assert.Equal(["version"], call));
        Assert.Empty(runtime.AcpCalls);
    }

    [Fact]
    public async Task VersionWithJson_UsesNativePath_WithoutLegacyBridge()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        var originalOut = Console.Out;
        using var writer = new StringWriter();
        Console.SetOut(writer);

        try
        {
            var exitCode = await CaiCli.RunAsync(["version", "--json"], runtime, cancellationToken);

            Assert.Equal(0, exitCode);
            Assert.Empty(runtime.LegacyCalls);
            Assert.Empty(runtime.AcpCalls);

            using var payload = JsonDocument.Parse(writer.ToString());
            Assert.True(payload.RootElement.TryGetProperty("version", out var versionElement));
            Assert.False(string.IsNullOrWhiteSpace(versionElement.GetString()));
            Assert.True(payload.RootElement.TryGetProperty("install_type", out _));
            Assert.True(payload.RootElement.TryGetProperty("install_dir", out _));
        }
        finally
        {
            Console.SetOut(originalOut);
        }
    }

    [Theory]
    [InlineData("--help")]
    [InlineData("-h")]
    public async Task HelpParserTokens_AreHandledByParser(string token)
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync([token], runtime, cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Empty(runtime.LegacyCalls);
        Assert.Empty(runtime.AcpCalls);
    }

    [Theory]
    [InlineData("--version")]
    [InlineData("-v")]
    public async Task VersionFlags_RouteToVersionCommand(string token)
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync([token], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.LegacyExitCode, exitCode);
        Assert.Collection(
            runtime.LegacyCalls,
            call => Assert.Equal(["version"], call));
        Assert.Empty(runtime.AcpCalls);
    }

    [Theory]
    [InlineData("--version")]
    [InlineData("-v")]
    public async Task VersionFlags_WithJson_UseNativeVersionJson(string token)
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        var originalOut = Console.Out;
        using var writer = new StringWriter();
        Console.SetOut(writer);

        try
        {
            var exitCode = await CaiCli.RunAsync([token, "--json"], runtime, cancellationToken);

            Assert.Equal(0, exitCode);
            Assert.Empty(runtime.LegacyCalls);
            Assert.Empty(runtime.AcpCalls);

            using var payload = JsonDocument.Parse(writer.ToString());
            Assert.True(payload.RootElement.TryGetProperty("version", out _));
            Assert.True(payload.RootElement.TryGetProperty("install_type", out _));
            Assert.True(payload.RootElement.TryGetProperty("install_dir", out _));
        }
        finally
        {
            Console.SetOut(originalOut);
        }
    }

    private sealed class FakeRuntime : ICaiCommandRuntime
    {
        public const int RunExitCode = 31;
        public const int ShellExitCode = 32;
        public const int ExecExitCode = 33;
        public const int DockerExitCode = 34;
        public const int StatusExitCode = 35;
        public const int LegacyExitCode = 17;
        public const int AcpExitCode = 23;

        public List<RunCommandOptions> RunCalls { get; } = [];

        public List<ShellCommandOptions> ShellCalls { get; } = [];

        public List<ExecCommandOptions> ExecCalls { get; } = [];

        public List<DockerCommandOptions> DockerCalls { get; } = [];

        public List<StatusCommandOptions> StatusCalls { get; } = [];

        public List<IReadOnlyList<string>> LegacyCalls { get; } = [];

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

        public Task<int> RunLegacyAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        {
            LegacyCalls.Add(args.ToArray());
            return Task.FromResult(LegacyExitCode);
        }

        public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        {
            AcpCalls.Add(agent);
            return Task.FromResult(AcpExitCode);
        }
    }
}
