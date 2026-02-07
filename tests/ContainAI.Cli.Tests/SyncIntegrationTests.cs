using System.Diagnostics;
using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class SyncIntegrationCollection
{
    public const string Name = "SyncIntegration";
}

[Collection(SyncIntegrationCollection.Name)]
public sealed class SyncIntegrationTests
{
    private const string AlpineImage = "alpine:3.20";

    [Fact]
    [Trait("Category", "SyncIntegration")]
    public async Task Import_FromDirectory_CopiesCoreFilesAndEnforcesSecretPermissions()
    {
        if (!await DockerAvailableAsync(TestContext.Current.CancellationToken))
        {
            return;
        }

        var volume = $"containai-test-sync-{Guid.NewGuid():N}";
        var sourceRoot = Path.Combine(Path.GetTempPath(), $"cai-sync-src-{Guid.NewGuid():N}");
        Directory.CreateDirectory(sourceRoot);

        try
        {
            Directory.CreateDirectory(Path.Combine(sourceRoot, ".claude"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".claude", "settings.json"), "{\"marker\":\"sync\"}", TestContext.Current.CancellationToken);
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".claude", ".credentials.json"), "{\"token\":\"secret\"}", TestContext.Current.CancellationToken);
            Directory.CreateDirectory(Path.Combine(sourceRoot, ".config", "gh"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".config", "gh", "hosts.yml"), "github.com:\n  user: test\n", TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(
                ["import", "--data-volume", volume, "--from", sourceRoot],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);

            var inspect = await RunDockerAsync(
                [
                    "run", "--rm", "-v", $"{volume}:/data", AlpineImage, "sh", "-lc",
                    "set -eu; test -f /data/claude/settings.json; test -f /data/claude/credentials.json; test -d /data/config/gh; stat -c '%a' /data/claude/credentials.json; stat -c '%a' /data/config/gh"
                ],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, inspect.ExitCode);
            var modes = SplitNonEmptyLines(inspect.StandardOutput);
            Assert.True(modes.Count >= 2);
            Assert.Equal("600", modes[0]);
            Assert.Equal("700", modes[1]);
        }
        finally
        {
            Directory.Delete(sourceRoot, recursive: true);
            _ = await RunDockerAsync(["volume", "rm", "-f", volume], TestContext.Current.CancellationToken);
        }
    }

    [Fact]
    [Trait("Category", "SyncIntegration")]
    public async Task Import_RejectsAbsoluteEnvFilePath()
    {
        if (!await DockerAvailableAsync(TestContext.Current.CancellationToken))
        {
            return;
        }

        var volume = $"containai-test-env-abs-{Guid.NewGuid():N}";
        var sourceRoot = Path.Combine(Path.GetTempPath(), $"cai-env-src-{Guid.NewGuid():N}");
        var workspace = Path.Combine(Path.GetTempPath(), $"cai-env-work-{Guid.NewGuid():N}");
        Directory.CreateDirectory(sourceRoot);
        Directory.CreateDirectory(workspace);

        try
        {
            Directory.CreateDirectory(Path.Combine(sourceRoot, ".claude"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".claude", "settings.json"), "{}", TestContext.Current.CancellationToken);

            var configPath = Path.Combine(workspace, "containai.toml");
            await File.WriteAllTextAsync(
                configPath,
                $$"""
                [agent]
                data_volume = "{{volume}}"

                [env]
                import = ["SOME_VAR"]
                from_host = false
                env_file = "/etc/passwd"
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(
                ["import", "--data-volume", volume, "--from", sourceRoot, "--workspace", workspace, "--config", configPath],
                TestContext.Current.CancellationToken);

            Assert.Equal(1, exitCode);
            Assert.Contains("path rejected", stderr.ToString(), StringComparison.Ordinal);
            Assert.Contains("workspace-relative", stderr.ToString(), StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(sourceRoot, recursive: true);
            Directory.Delete(workspace, recursive: true);
            _ = await RunDockerAsync(["volume", "rm", "-f", volume], TestContext.Current.CancellationToken);
        }
    }

    [Fact]
    [Trait("Category", "SyncIntegration")]
    public async Task Import_RejectsSymlinkedVolumeEnvTarget()
    {
        if (!await DockerAvailableAsync(TestContext.Current.CancellationToken))
        {
            return;
        }

        var volume = $"containai-test-env-symlink-{Guid.NewGuid():N}";
        var sourceRoot = Path.Combine(Path.GetTempPath(), $"cai-env-sym-src-{Guid.NewGuid():N}");
        var workspace = Path.Combine(Path.GetTempPath(), $"cai-env-sym-work-{Guid.NewGuid():N}");
        Directory.CreateDirectory(sourceRoot);
        Directory.CreateDirectory(workspace);

        try
        {
            Directory.CreateDirectory(Path.Combine(sourceRoot, ".claude"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".claude", "settings.json"), "{}", TestContext.Current.CancellationToken);
            await File.WriteAllTextAsync(Path.Combine(workspace, "test.env"), "SYNC_TEST_VAR=from_file\n", TestContext.Current.CancellationToken);

            var createVolume = await RunDockerAsync(["volume", "create", volume], TestContext.Current.CancellationToken);
            Assert.Equal(0, createVolume.ExitCode);

            var seed = await RunDockerAsync(
                ["run", "--rm", "-v", $"{volume}:/data", AlpineImage, "sh", "-lc", "set -eu; echo 'SYNC_TEST_VAR=old' > /data/real.env; ln -sf real.env /data/.env"],
                TestContext.Current.CancellationToken);
            Assert.Equal(0, seed.ExitCode);

            var configPath = Path.Combine(workspace, "containai.toml");
            await File.WriteAllTextAsync(
                configPath,
                $$"""
                [agent]
                data_volume = "{{volume}}"

                [env]
                import = ["SYNC_TEST_VAR"]
                from_host = false
                env_file = "test.env"
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(
                ["import", "--data-volume", volume, "--from", sourceRoot, "--workspace", workspace, "--config", configPath],
                TestContext.Current.CancellationToken);

            Assert.Equal(1, exitCode);
            Assert.Contains("target is symlink", stderr.ToString(), StringComparison.Ordinal);

            var verify = await RunDockerAsync(
                ["run", "--rm", "-v", $"{volume}:/data", AlpineImage, "sh", "-lc", "set -eu; test -L /data/.env; readlink /data/.env"],
                TestContext.Current.CancellationToken);
            Assert.Equal(0, verify.ExitCode);
            Assert.Contains("real.env", verify.StandardOutput, StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(sourceRoot, recursive: true);
            Directory.Delete(workspace, recursive: true);
            _ = await RunDockerAsync(["volume", "rm", "-f", volume], TestContext.Current.CancellationToken);
        }
    }

    [Fact]
    [Trait("Category", "SyncIntegration")]
    public async Task Import_SymlinkDirectoryConflict_ReportsNonEmptyDirectoryPitfall()
    {
        if (!await DockerAvailableAsync(TestContext.Current.CancellationToken))
        {
            return;
        }

        var volume = $"containai-test-symlink-pitfall-{Guid.NewGuid():N}";
        var sourceRoot = Path.Combine(Path.GetTempPath(), $"cai-pitfall-src-{Guid.NewGuid():N}");
        Directory.CreateDirectory(sourceRoot);

        try
        {
            var createVolume = await RunDockerAsync(["volume", "create", volume], TestContext.Current.CancellationToken);
            Assert.Equal(0, createVolume.ExitCode);

            var seed = await RunDockerAsync(
                [
                    "run", "--rm", "-v", $"{volume}:/data", AlpineImage, "sh", "-lc",
                    "set -eu; mkdir -p /data/editors/vim/subdir; echo old > /data/editors/vim/subdir/existing.txt"
                ],
                TestContext.Current.CancellationToken);
            Assert.Equal(0, seed.ExitCode);

            Directory.CreateDirectory(Path.Combine(sourceRoot, ".vim", "real-subdir"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".vim", "real-subdir", "new.txt"), "new content", TestContext.Current.CancellationToken);
            File.CreateSymbolicLink(
                Path.Combine(sourceRoot, ".vim", "subdir"),
                Path.Combine(sourceRoot, ".vim", "real-subdir"));

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(
                ["import", "--data-volume", volume, "--from", sourceRoot],
                TestContext.Current.CancellationToken);

            Assert.Equal(1, exitCode);
            var error = stderr.ToString();
            Assert.True(
                error.Contains("cannot delete non-empty directory", StringComparison.Ordinal) ||
                error.Contains("could not make way for new symlink", StringComparison.Ordinal),
                $"Expected pitfall error signature, got: {error}");
        }
        finally
        {
            Directory.Delete(sourceRoot, recursive: true);
            _ = await RunDockerAsync(["volume", "rm", "-f", volume], TestContext.Current.CancellationToken);
        }
    }

    [Fact]
    public void NativeLifecycleSource_ContainsEnvGuardMessages()
    {
        var sourcePath = LocateRepositoryPath("src", "cai", "NativeLifecycleCommandRuntime.cs");
        var source = File.ReadAllText(sourcePath);

        Assert.Contains(".env target is symlink", source, StringComparison.Ordinal);
        Assert.Contains("env_file path rejected: outside workspace boundary", source, StringComparison.Ordinal);
    }

    private static string LocateRepositoryPath(params string[] segments)
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            var candidate = Path.Combine(current.FullName, "src");
            if (Directory.Exists(candidate))
            {
                return Path.Combine(current.FullName, Path.Combine(segments));
            }

            current = current.Parent;
        }

        throw new DirectoryNotFoundException("Unable to locate repository root from AppContext.BaseDirectory.");
    }

    private static List<string> SplitNonEmptyLines(string text)
    {
        return text
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .ToList();
    }

    private static async Task<bool> DockerAvailableAsync(CancellationToken cancellationToken)
    {
        var version = await RunProcessAsync("docker", ["--version"], cancellationToken);
        if (version.ExitCode != 0)
        {
            return false;
        }

        var info = await RunDockerAsync(["info"], cancellationToken);
        return info.ExitCode == 0;
    }

    private static async Task<ProcessResult> RunDockerAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var context = await ResolveDockerContextAsync(cancellationToken);
        var dockerArgs = new List<string>();
        if (!string.IsNullOrWhiteSpace(context))
        {
            dockerArgs.Add("--context");
            dockerArgs.Add(context);
        }

        dockerArgs.AddRange(args);
        return await RunProcessAsync("docker", dockerArgs, cancellationToken);
    }

    private static async Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
    {
        foreach (var context in new[] { "containai-docker", "containai-secure", "docker-containai" })
        {
            var probe = await RunProcessAsync("docker", ["context", "inspect", context], cancellationToken);
            if (probe.ExitCode == 0)
            {
                return context;
            }
        }

        return null;
    }

    private static async Task<ProcessResult> RunProcessAsync(string fileName, IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        try
        {
            using var process = new Process
            {
                StartInfo =
                {
                    FileName = fileName,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                },
            };

            foreach (var arg in args)
            {
                process.StartInfo.ArgumentList.Add(arg);
            }

            process.Start();

            var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken);

            return new ProcessResult(process.ExitCode, await stdoutTask, await stderrTask);
        }
        catch (Exception ex)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
    }

    private sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError);
}
