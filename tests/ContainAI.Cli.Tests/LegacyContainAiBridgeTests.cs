using ContainAI.Cli;
using Xunit;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Tests;

public sealed class LegacyContainAiBridgeTests
{
    [Fact]
    public async Task InvokeAsync_SourcesScriptAndForwardsArgs()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var tempDirectory = Path.Combine(Path.GetTempPath(), $"cai-bridge-test-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDirectory);

        try
        {
            var scriptPath = Path.Combine(tempDirectory, "containai.sh");
            var outputPath = Path.Combine(tempDirectory, "output.txt");

            await File.WriteAllTextAsync(scriptPath, """
#!/usr/bin/env bash
containai() {
  printf '%s\n' "$*" > "$CAI_TEST_OUTPUT"
  return 7
}
""", cancellationToken);

            var resolver = new StaticScriptResolver(scriptPath);
            var bridge = new LegacyContainAiBridge(resolver);

            Environment.SetEnvironmentVariable("CAI_TEST_OUTPUT", outputPath);
            try
            {
                var exitCode = await bridge.InvokeAsync(["run", "--fresh", "/tmp/workspace"], cancellationToken);

                Assert.Equal(7, exitCode);
                Assert.Equal("run --fresh /tmp/workspace\n", await File.ReadAllTextAsync(outputPath, cancellationToken));
            }
            finally
            {
                Environment.SetEnvironmentVariable("CAI_TEST_OUTPUT", null);
            }
        }
        finally
        {
            Directory.Delete(tempDirectory, recursive: true);
        }
    }

    [Fact]
    public async Task InvokeAsync_WhenResolverThrows_PropagatesFailure()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var expected = new FileNotFoundException("missing containai.sh");
        var resolver = new ThrowingScriptResolver(expected);
        var bridge = new LegacyContainAiBridge(resolver);

        var exception = await Assert.ThrowsAsync<FileNotFoundException>(
            () => bridge.InvokeAsync(["run"], cancellationToken));

        Assert.Same(expected, exception);
        Assert.Equal(1, resolver.CallCount);
    }

    [Fact]
    public async Task InvokeAsync_WhenResolverReturnsMissingScript_ReturnsNonZeroExitCode()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var missingScriptPath = Path.Combine(Path.GetTempPath(), $"missing-containai-{Guid.NewGuid():N}.sh");
        var resolver = new StaticScriptResolver(missingScriptPath);
        var bridge = new LegacyContainAiBridge(resolver);

        var exitCode = await bridge.InvokeAsync(["run"], cancellationToken);

        Assert.NotEqual(0, exitCode);
    }

    private sealed class StaticScriptResolver : IContainAiScriptResolver
    {
        private readonly string _scriptPath;

        public StaticScriptResolver(string scriptPath)
        {
            _scriptPath = scriptPath;
        }

        public string ResolveScriptPath() => _scriptPath;
    }

    private sealed class ThrowingScriptResolver : IContainAiScriptResolver
    {
        private readonly Exception _exception;

        public ThrowingScriptResolver(Exception exception)
        {
            _exception = exception;
        }

        public int CallCount { get; private set; }

        public string ResolveScriptPath()
        {
            CallCount++;
            throw _exception;
        }
    }
}
