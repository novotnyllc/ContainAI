using System.Text.Json;
using ContainAI.Cli;
using ContainAI.Cli.Abstractions;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class CaiCliRoutingTests
{
    [Fact]
    public async Task NoArgs_UsesLegacyRuntime_DefaultRun()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync([], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.LegacyExitCode, exitCode);
        Assert.Single(runtime.LegacyCalls);
        Assert.Empty(runtime.LegacyCalls[0]);
    }

    [Fact]
    public async Task KnownCommand_UsesLegacyRuntime_WithForwardedTokens()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["run", "--fresh", "/tmp/workspace"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.LegacyExitCode, exitCode);
        Assert.Collection(
            runtime.LegacyCalls,
            call => Assert.Equal(["run", "--fresh", "/tmp/workspace"], call));
    }

    [Fact]
    public async Task KnownCommand_UnknownSubcommand_IsForwardedToLegacyRuntime()
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
        public const int LegacyExitCode = 17;
        public const int AcpExitCode = 23;

        public List<IReadOnlyList<string>> LegacyCalls { get; } = [];

        public List<string> AcpCalls { get; } = [];

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
