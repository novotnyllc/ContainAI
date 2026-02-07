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
    public async Task RunCommand_UsesNativeLifecycleRouting()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["run", "--fresh", "--detached", "echo", "ok"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.RunExitCode, exitCode);
        Assert.Single(runtime.RunCalls);
        Assert.True(runtime.RunCalls[0].Fresh);
        Assert.True(runtime.RunCalls[0].Detached);
        Assert.Equal(["echo", "ok"], runtime.RunCalls[0].CommandArgs);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task ShellCommand_UsesNativeLifecycleRouting()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["shell", "--workspace", "/tmp/workspace"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.ShellExitCode, exitCode);
        Assert.Single(runtime.ShellCalls);
        Assert.Equal("/tmp/workspace", runtime.ShellCalls[0].Workspace);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task ExecCommand_UsesNativeLifecycleRouting()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["exec", "ssh-target", "echo", "hi"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.ExecExitCode, exitCode);
        Assert.Single(runtime.ExecCalls);
        Assert.Equal(["ssh-target", "echo", "hi"], runtime.ExecCalls[0].CommandArgs);
        Assert.Empty(runtime.NativeCalls);
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
    public async Task StatusCommand_UnknownOption_ReturnsParserError()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["status", "--not-a-real-option"], runtime, cancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.StatusCalls);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task RunCommand_OptionLikeToken_IsTreatedAsCommandArg()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["run", "--not-a-real-option"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.RunExitCode, exitCode);
        Assert.Single(runtime.RunCalls);
        Assert.Equal(["--not-a-real-option"], runtime.RunCalls[0].CommandArgs);
    }

    [Fact]
    public async Task ShellCommand_OptionLikeToken_IsTreatedAsPositionalPath()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["shell", "--not-a-real-option"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.ShellExitCode, exitCode);
        Assert.Single(runtime.ShellCalls);
        Assert.Equal("--not-a-real-option", runtime.ShellCalls[0].Workspace);
    }

    [Fact]
    public async Task ExecCommand_OptionLikeToken_IsTreatedAsCommandArg()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["exec", "--not-a-real-option"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.ExecExitCode, exitCode);
        Assert.Single(runtime.ExecCalls);
        Assert.Equal(["--not-a-real-option"], runtime.ExecCalls[0].CommandArgs);
    }

    [Fact]
    public async Task NativeLifecycleCommand_UnknownSubcommand_ReturnsParserError()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["config", "mystery-subcommand", "--json"], runtime, cancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task ConfigCommand_UsesNativeLifecycleRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["config", "set", "agent.default", "claude"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["config", "set", "agent.default", "claude"], call));
    }

    [Fact]
    public async Task CompletionCommand_Bash_EmitsNativeSystemCommandLineScript()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        var originalOut = Console.Out;
        using var writer = new StringWriter();
        Console.SetOut(writer);

        try
        {
            var exitCode = await CaiCli.RunAsync(["completion", "bash"], runtime, cancellationToken);
            Assert.Equal(0, exitCode);
            Assert.Contains("cai completion suggest", writer.ToString(), StringComparison.Ordinal);
            Assert.Empty(runtime.NativeCalls);
        }
        finally
        {
            Console.SetOut(originalOut);
        }
    }

    [Fact]
    public async Task CompletionCommand_Zsh_EmitsNativeSystemCommandLineScript()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        var originalOut = Console.Out;
        using var writer = new StringWriter();
        Console.SetOut(writer);

        try
        {
            var exitCode = await CaiCli.RunAsync(["completion", "zsh"], runtime, cancellationToken);
            Assert.Equal(0, exitCode);
            Assert.Contains("#compdef cai", writer.ToString(), StringComparison.Ordinal);
            Assert.Contains("cai completion suggest", writer.ToString(), StringComparison.Ordinal);
            Assert.Empty(runtime.NativeCalls);
        }
        finally
        {
            Console.SetOut(originalOut);
        }
    }

    [Fact]
    public async Task CompletionCommand_Suggest_ReturnsContextualSuggestions()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        var originalOut = Console.Out;
        using var writer = new StringWriter();
        Console.SetOut(writer);

        try
        {
            var exitCode = await CaiCli.RunAsync(
                ["completion", "suggest", "--line", "cai st", "--position", "6"],
                runtime,
                cancellationToken);

            Assert.Equal(0, exitCode);
            var output = writer.ToString();
            Assert.Contains("status", output, StringComparison.Ordinal);
            Assert.Contains("stop", output, StringComparison.Ordinal);
            Assert.DoesNotContain("completion", output, StringComparison.Ordinal);
            Assert.Empty(runtime.NativeCalls);
        }
        finally
        {
            Console.SetOut(originalOut);
        }
    }

    [Fact]
    public async Task CompletionCommand_Suggest_SupportsAbsoluteCommandPathInput()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        var originalOut = Console.Out;
        using var writer = new StringWriter();
        Console.SetOut(writer);

        try
        {
            var exitCode = await CaiCli.RunAsync(
                ["completion", "suggest", "--line", "/usr/local/bin/cai st", "--position", "21"],
                runtime,
                cancellationToken);

            Assert.Equal(0, exitCode);
            Assert.Contains("status", writer.ToString(), StringComparison.Ordinal);
            Assert.Empty(runtime.NativeCalls);
        }
        finally
        {
            Console.SetOut(originalOut);
        }
    }

    [Fact]
    public async Task SystemCommand_UsesNativeLifecycleRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["system", "init", "--quiet"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["system", "init", "--quiet"], call));
    }

    [Fact]
    public async Task UnknownFirstToken_UsesImplicitRunRouting()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["mystery", "token"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.RunExitCode, exitCode);
        Assert.Single(runtime.RunCalls);
        Assert.Equal(["mystery", "token"], runtime.RunCalls[0].CommandArgs);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task FlagFirstToken_UsesImplicitRunRouting()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--fresh", "/tmp/workspace"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.RunExitCode, exitCode);
        Assert.Single(runtime.RunCalls);
        Assert.True(runtime.RunCalls[0].Fresh);
        Assert.Equal(["/tmp/workspace"], runtime.RunCalls[0].CommandArgs);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task AcpProxy_Subcommand_UsesAcpRuntime_WithExplicitAgent()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["acp", "proxy", "gemini"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.AcpExitCode, exitCode);
        Assert.Equal(["gemini"], runtime.AcpCalls);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task AcpProxy_Subcommand_DefaultsAgentToClaude()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["acp", "proxy"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.AcpExitCode, exitCode);
        Assert.Equal(["claude"], runtime.AcpCalls);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task LegacyAcpFlag_IsMappedToAcpRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--acp", "claude"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.AcpExitCode, exitCode);
        Assert.Equal(["claude"], runtime.AcpCalls);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task LegacyAcpFlag_WithoutAgent_DefaultsToClaude()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--acp"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.AcpExitCode, exitCode);
        Assert.Equal(["claude"], runtime.AcpCalls);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task LegacyAcpFlag_WithHelp_IsHandledByParserWithoutRuntimeInvocation()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--acp", "--help"], runtime, cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Empty(runtime.AcpCalls);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task AcpCommand_UnknownSubcommand_ReturnsErrorWithoutInvokingRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["acp", "mystery-subcommand"], runtime, cancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.AcpCalls);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task AcpProxy_WithAdditionalArgument_ReturnsParserError()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["acp", "proxy", "claude", "extra"], runtime, cancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.AcpCalls);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task RefreshAlias_IsNormalizedToRefreshSubcommand()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--refresh", "--rebuild"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["refresh", "--rebuild"], call));
    }

    [Fact]
    public async Task RefreshAlias_WithoutOptions_IsNormalizedToRefreshSubcommand()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--refresh"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["refresh"], call));
    }

    [Fact]
    public async Task HelpSubcommand_UsesNativeRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["help"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["help"], call));
        Assert.Empty(runtime.AcpCalls);
    }

    [Fact]
    public async Task VersionSubcommand_UsesNativeRuntime_WhenJsonNotRequested()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["version"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
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
            Assert.Empty(runtime.NativeCalls);
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

    [Fact]
    public async Task Version_UnknownOption_ReturnsParserError()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["version", "--bogus"], runtime, cancellationToken);

        Assert.NotEqual(0, exitCode);
        Assert.Empty(runtime.NativeCalls);
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
        Assert.Empty(runtime.NativeCalls);
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

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
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
            Assert.Empty(runtime.NativeCalls);
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
        public const int NativeExitCode = 36;
        public const int AcpExitCode = 23;

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

        public Task<int> RunNativeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        {
            NativeCalls.Add(args.ToArray());
            return Task.FromResult(NativeExitCode);
        }

        public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        {
            AcpCalls.Add(agent);
            return Task.FromResult(AcpExitCode);
        }
    }
}
