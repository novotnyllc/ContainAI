using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class ContainerRuntimeCommandTests
{
    [Fact]
    public async Task SystemDevcontainerInstall_Help_ReturnsUsage()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

        var exitCode = await runtime.RunAsync(
            ["system", "devcontainer", "install", "--help"],
            TestContext.Current.CancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Contains("system devcontainer install", stdout.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task SystemLinkRepair_CheckReturnsFailureWhenLinkIsMissing()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"cai-system-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var specPath = Path.Combine(tempDir, "link-spec.json");
            var checkedAtPath = Path.Combine(tempDir, ".links-checked-at");
            var linkPath = Path.Combine(tempDir, "missing-link");
            var targetPath = Path.Combine(tempDir, "target.txt");

            await File.WriteAllTextAsync(targetPath, "content", TestContext.Current.CancellationToken);
            await File.WriteAllTextAsync(
                specPath,
                $$"""
                  {
                    "version": 1,
                    "data_mount": "/mnt/agent-data",
                    "home_dir": "/home/agent",
                    "links": [
                      {
                        "link": "{{linkPath}}",
                        "target": "{{targetPath}}",
                        "remove_first": false
                      }
                    ]
                  }
                  """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(
                ["system", "link-repair", "--check", "--builtin-spec", specPath, "--user-spec", Path.Combine(tempDir, "missing-user-spec.json"), "--checked-at-file", checkedAtPath],
                TestContext.Current.CancellationToken);

            Assert.Equal(1, exitCode);
            Assert.Contains("[MISSING]", stdout.ToString(), StringComparison.Ordinal);
            Assert.False(File.Exists(checkedAtPath));
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public async Task SystemLinkRepair_FixCreatesSymlinkAndWritesTimestamp()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"cai-system-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var specPath = Path.Combine(tempDir, "link-spec.json");
            var checkedAtPath = Path.Combine(tempDir, ".links-checked-at");
            var linkPath = Path.Combine(tempDir, "created-link");
            var targetPath = Path.Combine(tempDir, "target.txt");

            await File.WriteAllTextAsync(targetPath, "content", TestContext.Current.CancellationToken);
            await File.WriteAllTextAsync(
                specPath,
                $$"""
                  {
                    "version": 1,
                    "data_mount": "/mnt/agent-data",
                    "home_dir": "/home/agent",
                    "links": [
                      {
                        "link": "{{linkPath}}",
                        "target": "{{targetPath}}",
                        "remove_first": false
                      }
                    ]
                  }
                  """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(
                ["system", "link-repair", "--fix", "--builtin-spec", specPath, "--user-spec", Path.Combine(tempDir, "missing-user-spec.json"), "--checked-at-file", checkedAtPath],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);
            Assert.True(File.Exists(checkedAtPath));
            Assert.True(File.Exists(linkPath) || Directory.Exists(linkPath));
            Assert.True((File.GetAttributes(linkPath) & FileAttributes.ReparsePoint) != 0);
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }
}
