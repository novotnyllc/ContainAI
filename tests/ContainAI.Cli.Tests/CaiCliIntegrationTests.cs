using System.Text.Json;
using ContainAI.Cli;
using ContainAI.Cli.Abstractions;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class CaiCliIntegrationTests
{
    [Fact]
    public async Task KnownCommand_UsesRealLegacyBridgeAndForwardsTokens()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-cli-integration-run");
        var scriptPath = await WriteBridgeScriptAsync(temp.Path, TestContext.Current.CancellationToken);
        var outputPath = Path.Combine(temp.Path, "legacy-output.txt");
        var runtime = CreateRuntime(scriptPath, outputPath);
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["run", "--fresh", "/tmp/workspace"], runtime, cancellationToken);

        Assert.Equal(11, exitCode);
        var captured = await File.ReadAllTextAsync(outputPath, cancellationToken);
        Assert.Equal("run --fresh /tmp/workspace\n", captured);
    }

    [Fact]
    public async Task VersionWithoutJson_UsesRealLegacyBridge()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-cli-integration-version");
        var scriptPath = await WriteBridgeScriptAsync(temp.Path, TestContext.Current.CancellationToken);
        var outputPath = Path.Combine(temp.Path, "legacy-output.txt");
        var runtime = CreateRuntime(scriptPath, outputPath);
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["version"], runtime, cancellationToken);

        Assert.Equal(11, exitCode);
        var captured = await File.ReadAllTextAsync(outputPath, cancellationToken);
        Assert.Equal("version\n", captured);
    }

    [Fact]
    public async Task VersionJson_UsesNativePathAndDoesNotInvokeLegacyBridge()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-cli-integration-version-json");
        var scriptPath = await WriteBridgeScriptAsync(temp.Path, TestContext.Current.CancellationToken);
        var outputPath = Path.Combine(temp.Path, "legacy-output.txt");
        var runtime = CreateRuntime(scriptPath, outputPath);
        var cancellationToken = TestContext.Current.CancellationToken;
        var originalOut = Console.Out;
        using var writer = new StringWriter();
        Console.SetOut(writer);

        try
        {
            var exitCode = await CaiCli.RunAsync(["version", "--json"], runtime, cancellationToken);

            Assert.Equal(0, exitCode);
            Assert.False(File.Exists(outputPath));

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

    [Fact]
    public async Task AcpProxyPath_DoesNotInvokeLegacyBridge()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-cli-integration-acp");
        var scriptPath = await WriteBridgeScriptAsync(temp.Path, TestContext.Current.CancellationToken);
        var outputPath = Path.Combine(temp.Path, "legacy-output.txt");
        var runtime = CreateRuntime(scriptPath, outputPath);
        var cancellationToken = TestContext.Current.CancellationToken;

        var exitCode = await CaiCli.RunAsync(["acp", "proxy", "gemini"], runtime, cancellationToken);

        Assert.Equal(29, exitCode);
        Assert.Equal(["gemini"], runtime.AcpCalls);
        Assert.False(File.Exists(outputPath));
    }

    private static IntegrationRuntime CreateRuntime(string scriptPath, string outputPath)
    {
        var resolver = new StaticScriptResolver(scriptPath);
        var bridge = new LegacyContainAiBridge(resolver);
        return new IntegrationRuntime(bridge, outputPath);
    }

    private static async Task<string> WriteBridgeScriptAsync(string tempRoot, CancellationToken cancellationToken)
    {
        var scriptPath = Path.Combine(tempRoot, "containai.sh");
        await File.WriteAllTextAsync(
            scriptPath,
            """
            #!/usr/bin/env bash
            containai() {
              printf '%s\n' "$*" > "$CAI_TEST_OUTPUT"
              return 11
            }
            """,
            cancellationToken);

        var chmod = await ShellTestSupport.RunBashAsync(
            $"chmod +x {ShellTestSupport.ShellQuote(scriptPath)}",
            cancellationToken: cancellationToken);

        Assert.Equal(0, chmod.ExitCode);
        return scriptPath;
    }

    private sealed class StaticScriptResolver : IContainAiScriptResolver
    {
        private readonly string _path;

        public StaticScriptResolver(string path)
        {
            _path = path;
        }

        public string ResolveScriptPath() => _path;
    }

    private sealed class IntegrationRuntime : ICaiCommandRuntime
    {
        private readonly ILegacyContainAiBridge _legacyBridge;
        private readonly string _outputPath;

        public IntegrationRuntime(ILegacyContainAiBridge legacyBridge, string outputPath)
        {
            _legacyBridge = legacyBridge;
            _outputPath = outputPath;
        }

        public List<string> AcpCalls { get; } = [];

        public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
        {
            var forwarded = new List<string> { "run" };
            if (options.Fresh)
            {
                forwarded.Add("--fresh");
            }

            forwarded.AddRange(options.AdditionalArgs);
            forwarded.AddRange(options.CommandArgs);
            return RunLegacyAsync(forwarded, cancellationToken);
        }

        public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
        {
            var forwarded = new List<string> { "shell" };
            forwarded.AddRange(options.AdditionalArgs);
            forwarded.AddRange(options.CommandArgs);
            return RunLegacyAsync(forwarded, cancellationToken);
        }

        public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
        {
            var forwarded = new List<string> { "exec" };
            forwarded.AddRange(options.AdditionalArgs);
            forwarded.AddRange(options.CommandArgs);
            return RunLegacyAsync(forwarded, cancellationToken);
        }

        public Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
        {
            var forwarded = new List<string> { "docker" };
            forwarded.AddRange(options.DockerArgs);
            return RunLegacyAsync(forwarded, cancellationToken);
        }

        public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
        {
            var forwarded = new List<string> { "status" };
            if (options.Json)
            {
                forwarded.Add("--json");
            }

            if (!string.IsNullOrWhiteSpace(options.Container))
            {
                forwarded.Add("--container");
                forwarded.Add(options.Container);
            }

            forwarded.AddRange(options.AdditionalArgs);
            return RunLegacyAsync(forwarded, cancellationToken);
        }

        public async Task<int> RunLegacyAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        {
            Environment.SetEnvironmentVariable("CAI_TEST_OUTPUT", _outputPath);
            try
            {
                return await _legacyBridge.InvokeAsync(args, cancellationToken);
            }
            finally
            {
                Environment.SetEnvironmentVariable("CAI_TEST_OUTPUT", null);
            }
        }

        public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        {
            AcpCalls.Add(agent);
            return Task.FromResult(29);
        }
    }
}
