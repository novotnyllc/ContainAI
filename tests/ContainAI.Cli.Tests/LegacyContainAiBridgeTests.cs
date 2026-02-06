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

    private sealed class StaticScriptResolver : IContainAiScriptResolver
    {
        private readonly string _scriptPath;

        public StaticScriptResolver(string scriptPath)
        {
            _scriptPath = scriptPath;
        }

        public string ResolveScriptPath() => _scriptPath;
    }
}
