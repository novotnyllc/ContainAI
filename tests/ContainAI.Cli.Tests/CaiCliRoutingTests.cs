using ContainAI.Cli;
using Xunit;
using ContainAI.Cli.Abstractions;

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
