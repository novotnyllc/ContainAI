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
        Assert.Empty(runtime.RunCalls[0].Env);
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
    public async Task ConfigCommand_Root_UsesNativeRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["config"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["config"], call));
    }

    [Fact]
    public async Task ConfigCommand_List_IncludesGlobalWorkspaceAndVerboseFlags()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["config", "--global", "--workspace", "/tmp/w", "--verbose", "list"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["config", "--global", "--workspace", "/tmp/w", "--verbose", "list"], call));
    }

    [Fact]
    public async Task ConfigCommand_GetAndUnset_ForwardKeyArguments()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var getExitCode = await CaiCli.RunAsync(["config", "get", "agent.default"], runtime, cancellationToken);
        var unsetExitCode = await CaiCli.RunAsync(["config", "unset", "agent.default"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, getExitCode);
        Assert.Equal(FakeRuntime.NativeExitCode, unsetExitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["config", "get", "agent.default"], call),
            call => Assert.Equal(["config", "unset", "agent.default"], call));
    }

    [Fact]
    public async Task ConfigCommand_ResolveVolume_ForwardsOptionalArgument()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["config", "resolve-volume", "explicit-vol"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["config", "resolve-volume", "explicit-vol"], call));
    }

    [Fact]
    public async Task InstallCommand_UsesTypedRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(
            ["install", "--local", "--yes", "--no-setup", "--install-dir", "/tmp/install", "--bin-dir", "/tmp/bin", "--channel", "stable", "--verbose"],
            runtime,
            cancellationToken);

        Assert.Equal(FakeRuntime.InstallExitCode, exitCode);
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
    public async Task ExamplesCommand_UsesTypedRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var listExitCode = await CaiCli.RunAsync(["examples"], runtime, cancellationToken);
        var exportExitCode = await CaiCli.RunAsync(["examples", "export", "--output-dir", "/tmp/examples", "--force"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.ExamplesListExitCode, listExitCode);
        Assert.Equal(FakeRuntime.ExamplesExportExitCode, exportExitCode);
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
    public async Task CompletionCommand_Suggest_ReturnsContextualSuggestions()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        using var console = new TestCaiConsole();

        var exitCode = await CaiCli.RunAsync(
            ["completion", "suggest", "--line", "cai st", "--position", "6"],
            runtime,
            console,
            cancellationToken);

        Assert.Equal(0, exitCode);
        var output = console.Output.ToString();
        Assert.Contains("status", output, StringComparison.Ordinal);
        Assert.Contains("stop", output, StringComparison.Ordinal);
        Assert.DoesNotContain("completion", output, StringComparison.Ordinal);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task CompletionCommand_Suggest_WithEmptyLine_CompletesWithoutRuntimeCalls()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        using var console = new TestCaiConsole();

        var exitCode = await CaiCli.RunAsync(
            ["completion", "suggest", "--line", string.Empty, "--position", "5"],
            runtime,
            console,
            cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task CompletionCommand_Suggest_WithNonCaiInvocation_CompletesWithoutRuntimeCalls()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        using var console = new TestCaiConsole();

        var exitCode = await CaiCli.RunAsync(
            ["completion", "suggest", "--line", "docker ru", "--position", "42"],
            runtime,
            console,
            cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task CompletionCommand_Suggest_WithCaiDockerPrefix_ReturnsDockerSuggestions()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        using var console = new TestCaiConsole();

        var exitCode = await CaiCli.RunAsync(
            ["completion", "suggest", "--line", "cai docker ru", "--position", "13"],
            runtime,
            console,
            cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Contains("run", console.Output.ToString(), StringComparison.Ordinal);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task CompletionCommand_Suggest_WithContainAiDockerPrefix_ReturnsDockerSuggestions()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        using var console = new TestCaiConsole();

        var exitCode = await CaiCli.RunAsync(
            ["completion", "suggest", "--line", "containai-docker ru", "--position", "19"],
            runtime,
            console,
            cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Contains("run", console.Output.ToString(), StringComparison.Ordinal);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task CompletionCommand_Suggest_WithFlagFirstInput_UsesImplicitRunOptions()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        using var console = new TestCaiConsole();

        var exitCode = await CaiCli.RunAsync(
            ["completion", "suggest", "--line", "cai --fr", "--position", "8"],
            runtime,
            console,
            cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Contains("--fresh", console.Output.ToString(), StringComparison.Ordinal);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task CompletionCommand_Suggest_SupportsAbsoluteCommandPathInput()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        using var console = new TestCaiConsole();

        var exitCode = await CaiCli.RunAsync(
            ["completion", "suggest", "--line", "/usr/local/bin/cai st", "--position", "21"],
            runtime,
            console,
            cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Contains("status", console.Output.ToString(), StringComparison.Ordinal);
        Assert.Empty(runtime.NativeCalls);
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
    public async Task SystemCommand_Root_UsesNativeRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["system"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["system"], call));
    }

    [Fact]
    public async Task SystemDevcontainerCommand_Root_UsesNativeRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["system", "devcontainer"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["system", "devcontainer"], call));
    }

    [Fact]
    public async Task LinksCommand_Root_UsesNativeRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["links"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["links"], call));
    }

    [Fact]
    public async Task ManifestCommand_Root_UsesNativeRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["manifest"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["manifest"], call));
    }

[Fact]
public async Task ManifestCheck_ForwardsCanonicalManifestDirOption()
{
    var runtime = new FakeRuntime();
    var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["manifest", "check", "src/manifests"], runtime, cancellationToken);

    Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
    Assert.Collection(
        runtime.NativeCalls,
        call => Assert.Equal(["manifest", "check", "--manifest-dir", "src/manifests"], call));
}

    [Fact]
    public async Task TemplateCommand_Root_UsesNativeRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["template"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["template"], call));
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
    public async Task AcpStyleFlag_IsTreatedAsRunArguments()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--acp", "claude"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.RunExitCode, exitCode);
        Assert.Single(runtime.RunCalls);
        Assert.Equal(["--acp", "claude"], runtime.RunCalls[0].CommandArgs);
        Assert.Empty(runtime.AcpCalls);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task AcpStyleFlag_WithoutAgent_IsTreatedAsRunArgument()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--acp"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.RunExitCode, exitCode);
        Assert.Single(runtime.RunCalls);
        Assert.Equal(["--acp"], runtime.RunCalls[0].CommandArgs);
        Assert.Empty(runtime.AcpCalls);
        Assert.Empty(runtime.NativeCalls);
    }

    [Fact]
    public async Task AcpStyleFlag_WithHelp_ShowsTopLevelHelpWithoutRuntimeInvocation()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["--acp", "--help"], runtime, cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Empty(runtime.RunCalls);
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
    public async Task HelpSubcommand_WithTopic_UsesNativeRuntime()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["help", "manifest"], runtime, cancellationToken);

        Assert.Equal(FakeRuntime.NativeExitCode, exitCode);
        Assert.Collection(
            runtime.NativeCalls,
            call => Assert.Equal(["help", "manifest"], call));
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
    public async Task VersionWithJson_UsesNativePathDirectly()
    {
        var runtime = new FakeRuntime();
        var cancellationToken = TestContext.Current.CancellationToken;
        using var console = new TestCaiConsole();

        var exitCode = await CaiCli.RunAsync(["version", "--json"], runtime, console, cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Empty(runtime.NativeCalls);
        Assert.Empty(runtime.AcpCalls);

        var output = console.Output.ToString();
        var jsonLine = output
            .Split(Environment.NewLine, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Last(static line => line.StartsWith('{'));

        using var payload = JsonDocument.Parse(jsonLine);
        Assert.True(payload.RootElement.TryGetProperty("version", out var versionElement));
        Assert.False(string.IsNullOrWhiteSpace(versionElement.GetString()));
        Assert.True(payload.RootElement.TryGetProperty("install_type", out _));
        Assert.True(payload.RootElement.TryGetProperty("install_dir", out _));
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
        using var console = new TestCaiConsole();

        var exitCode = await CaiCli.RunAsync([token, "--json"], runtime, console, cancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Empty(runtime.NativeCalls);
        Assert.Empty(runtime.AcpCalls);

        using var payload = JsonDocument.Parse(console.Output.ToString());
        Assert.True(payload.RootElement.TryGetProperty("version", out _));
        Assert.True(payload.RootElement.TryGetProperty("install_type", out _));
        Assert.True(payload.RootElement.TryGetProperty("install_dir", out _));
    }

    private sealed class TestCaiConsole : ICaiConsole, IDisposable
    {
        public StringWriter Output { get; } = new();

        public TextWriter OutputWriter => Output;

        public TextWriter ErrorWriter { get; } = TextWriter.Null;

        public void Dispose() => Output.Dispose();
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
        public const int InstallExitCode = 24;
        public const int ExamplesListExitCode = 25;
        public const int ExamplesExportExitCode = 26;

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
}
