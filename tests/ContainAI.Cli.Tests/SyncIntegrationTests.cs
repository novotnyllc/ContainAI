using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class SyncIntegrationGroup
{
    public const string Name = "SyncIntegration";
}

[Collection(SyncIntegrationGroup.Name)]
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
            var runtime = new CaiCommandRuntime(stdout, stderr);

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
            var runtime = new CaiCommandRuntime(stdout, stderr);

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
    public async Task Import_AdditionalPaths_SyncsFiles_AndFiltersPrivEntries()
    {
        if (!await DockerAvailableAsync(TestContext.Current.CancellationToken))
        {
            return;
        }

        var volume = $"containai-test-additional-{Guid.NewGuid():N}";
        var sourceRoot = Path.Combine(Path.GetTempPath(), $"cai-additional-src-{Guid.NewGuid():N}");
        var workspace = Path.Combine(Path.GetTempPath(), $"cai-additional-work-{Guid.NewGuid():N}");
        Directory.CreateDirectory(sourceRoot);
        Directory.CreateDirectory(workspace);

        try
        {
            Directory.CreateDirectory(Path.Combine(sourceRoot, ".claude"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".claude", "settings.json"), "{}", TestContext.Current.CancellationToken);

            Directory.CreateDirectory(Path.Combine(sourceRoot, ".bashrc.d"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".bashrc.d", "10-public.sh"), "export PUBLIC=1\n", TestContext.Current.CancellationToken);
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".bashrc.d", "20-secret.priv.sh"), "export SECRET=1\n", TestContext.Current.CancellationToken);

            Directory.CreateDirectory(Path.Combine(sourceRoot, ".config", "mytool"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".config", "mytool", "config.json"), """{"enabled":true}""", TestContext.Current.CancellationToken);

            var configPath = Path.Combine(workspace, "containai.toml");
            await File.WriteAllTextAsync(
                configPath,
                """
                [agent]
                data_volume = "__VOLUME__"

                [import]
                additional_paths = ["~/.bashrc.d", "~/.config/mytool/config.json"]
                """.Replace("__VOLUME__", volume, StringComparison.Ordinal),
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new CaiCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(
                ["import", "--data-volume", volume, "--from", sourceRoot, "--workspace", workspace, "--config", configPath],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);

            var verify = await RunDockerAsync(
                [
                    "run", "--rm", "-v", $"{volume}:/data", AlpineImage, "sh", "-lc",
                    "set -eu; test -f /data/bashrc.d/10-public.sh; test ! -f /data/bashrc.d/20-secret.priv.sh; test -f /data/config/mytool/config.json"
                ],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, verify.ExitCode);
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
    public async Task Import_EnvFileAndHostMerge_WritesAllowlistedValues()
    {
        if (!await DockerAvailableAsync(TestContext.Current.CancellationToken))
        {
            return;
        }

        var volume = $"containai-test-env-merge-{Guid.NewGuid():N}";
        var sourceRoot = Path.Combine(Path.GetTempPath(), $"cai-env-merge-src-{Guid.NewGuid():N}");
        var workspace = Path.Combine(Path.GetTempPath(), $"cai-env-merge-work-{Guid.NewGuid():N}");
        Directory.CreateDirectory(sourceRoot);
        Directory.CreateDirectory(workspace);

        var previousHostValue = Environment.GetEnvironmentVariable("SYNC_TEST_FROM_HOST");
        try
        {
            Directory.CreateDirectory(Path.Combine(sourceRoot, ".claude"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".claude", "settings.json"), "{}", TestContext.Current.CancellationToken);
            await File.WriteAllTextAsync(
                Path.Combine(workspace, "test.env"),
                "SYNC_TEST_FROM_FILE=file_value\nSYNC_TEST_FROM_HOST=file_host_value\nUNUSED_KEY=ignored\n",
                TestContext.Current.CancellationToken);

            Environment.SetEnvironmentVariable("SYNC_TEST_FROM_HOST", "host_value");

            var configPath = Path.Combine(workspace, "containai.toml");
            await File.WriteAllTextAsync(
                configPath,
                """
                [agent]
                data_volume = "__VOLUME__"

                [env]
                import = ["SYNC_TEST_FROM_FILE", "SYNC_TEST_FROM_HOST", "SYNC_TEST_MISSING"]
                from_host = true
                env_file = "test.env"
                """.Replace("__VOLUME__", volume, StringComparison.Ordinal),
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new CaiCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(
                ["import", "--data-volume", volume, "--from", sourceRoot, "--workspace", workspace, "--config", configPath],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);
            Assert.Contains("Missing host env var: SYNC_TEST_MISSING", stderr.ToString(), StringComparison.Ordinal);

            var inspect = await RunDockerAsync(
                ["run", "--rm", "-v", $"{volume}:/data", AlpineImage, "sh", "-lc", "set -eu; test -f /data/.env; cat /data/.env"],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, inspect.ExitCode);
            Assert.Contains("SYNC_TEST_FROM_FILE=file_value", inspect.StandardOutput, StringComparison.Ordinal);
            Assert.Contains("SYNC_TEST_FROM_HOST=host_value", inspect.StandardOutput, StringComparison.Ordinal);
            Assert.DoesNotContain("UNUSED_KEY=", inspect.StandardOutput, StringComparison.Ordinal);
        }
        finally
        {
            Environment.SetEnvironmentVariable("SYNC_TEST_FROM_HOST", previousHostValue);
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
            var runtime = new CaiCommandRuntime(stdout, stderr);

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
            var runtime = new CaiCommandRuntime(stdout, stderr);

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
    [Trait("Category", "SyncIntegration")]
    public async Task Import_NoExcludes_ControlsManifestExcludeRules()
    {
        if (!await DockerAvailableAsync(TestContext.Current.CancellationToken))
        {
            return;
        }

        var defaultVolume = $"containai-test-noex-default-{Guid.NewGuid():N}";
        var noExcludesVolume = $"containai-test-noex-all-{Guid.NewGuid():N}";
        var sourceRoot = Path.Combine(Path.GetTempPath(), $"cai-noex-src-{Guid.NewGuid():N}");
        Directory.CreateDirectory(sourceRoot);

        try
        {
            Directory.CreateDirectory(Path.Combine(sourceRoot, ".codex", "skills", ".system"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".codex", "skills", "user.md"), "user content\n", TestContext.Current.CancellationToken);
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".codex", "skills", ".system", "internal.md"), "internal content\n", TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new CaiCommandRuntime(stdout, stderr);

            var defaultExitCode = await runtime.RunAsync(
                ["import", "--data-volume", defaultVolume, "--from", sourceRoot],
                TestContext.Current.CancellationToken);
            Assert.Equal(0, defaultExitCode);

            var defaultVerify = await RunDockerAsync(
                [
                    "run", "--rm", "-v", $"{defaultVolume}:/data", AlpineImage, "sh", "-lc",
                    "set -eu; test -f /data/codex/skills/user.md; test ! -f /data/codex/skills/.system/internal.md"
                ],
                TestContext.Current.CancellationToken);
            Assert.Equal(0, defaultVerify.ExitCode);

            var noExcludesExitCode = await runtime.RunAsync(
                ["import", "--data-volume", noExcludesVolume, "--from", sourceRoot, "--no-excludes"],
                TestContext.Current.CancellationToken);
            Assert.Equal(0, noExcludesExitCode);

            var noExcludesVerify = await RunDockerAsync(
                [
                    "run", "--rm", "-v", $"{noExcludesVolume}:/data", AlpineImage, "sh", "-lc",
                    "set -eu; test -f /data/codex/skills/user.md; test -f /data/codex/skills/.system/internal.md"
                ],
                TestContext.Current.CancellationToken);
            Assert.Equal(0, noExcludesVerify.ExitCode);
        }
        finally
        {
            Directory.Delete(sourceRoot, recursive: true);
            _ = await RunDockerAsync(["volume", "rm", "-f", defaultVolume], TestContext.Current.CancellationToken);
            _ = await RunDockerAsync(["volume", "rm", "-f", noExcludesVolume], TestContext.Current.CancellationToken);
        }
    }

    [Fact]
    [Trait("Category", "SyncIntegration")]
    public async Task Import_NoSecrets_SkipsSecretManifestEntries_ButStillCopiesAdditionalPaths()
    {
        if (!await DockerAvailableAsync(TestContext.Current.CancellationToken))
        {
            return;
        }

        var volume = $"containai-test-nosecrets-{Guid.NewGuid():N}";
        var sourceRoot = Path.Combine(Path.GetTempPath(), $"cai-nosecrets-src-{Guid.NewGuid():N}");
        var workspace = Path.Combine(Path.GetTempPath(), $"cai-nosecrets-work-{Guid.NewGuid():N}");
        Directory.CreateDirectory(sourceRoot);
        Directory.CreateDirectory(workspace);

        try
        {
            Directory.CreateDirectory(Path.Combine(sourceRoot, ".codex"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".codex", "auth.json"), """{"token":"secret"}""", TestContext.Current.CancellationToken);
            Directory.CreateDirectory(Path.Combine(sourceRoot, ".extra"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".extra", "secret.txt"), "top secret\n", TestContext.Current.CancellationToken);

            var configPath = Path.Combine(workspace, "containai.toml");
            await File.WriteAllTextAsync(
                configPath,
                $$"""
                [agent]
                data_volume = "{{volume}}"

                [import]
                additional_paths = ["~/.extra/secret.txt"]
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new CaiCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(
                ["import", "--data-volume", volume, "--from", sourceRoot, "--workspace", workspace, "--config", configPath, "--no-secrets"],
                TestContext.Current.CancellationToken);
            Assert.Equal(0, exitCode);

            var verify = await RunDockerAsync(
                [
                    "run", "--rm", "-v", $"{volume}:/data", AlpineImage, "sh", "-lc",
                    "set -eu; test ! -f /data/codex/auth.json; test -f /data/extra/secret.txt"
                ],
                TestContext.Current.CancellationToken);
            Assert.Equal(0, verify.ExitCode);
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
    public async Task Import_InvalidTomlConfig_ReturnsParseError()
    {
        if (!await DockerAvailableAsync(TestContext.Current.CancellationToken))
        {
            return;
        }

        var volume = $"containai-test-badconfig-{Guid.NewGuid():N}";
        var sourceRoot = Path.Combine(Path.GetTempPath(), $"cai-badcfg-src-{Guid.NewGuid():N}");
        var workspace = Path.Combine(Path.GetTempPath(), $"cai-badcfg-work-{Guid.NewGuid():N}");
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
                [agent
                data_volume = "{{volume}}"
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new CaiCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(
                ["import", "--data-volume", volume, "--from", sourceRoot, "--workspace", workspace, "--config", configPath],
                TestContext.Current.CancellationToken);

            Assert.Equal(1, exitCode);
            Assert.Contains("Error: Invalid TOML", stderr.ToString(), StringComparison.Ordinal);
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
    public async Task Import_AdditionalPathWithSymlinkComponent_IsRejected()
    {
        if (!await DockerAvailableAsync(TestContext.Current.CancellationToken))
        {
            return;
        }

        var volume = $"containai-test-additional-symlink-{Guid.NewGuid():N}";
        var sourceRoot = Path.Combine(Path.GetTempPath(), $"cai-additional-sym-src-{Guid.NewGuid():N}");
        var workspace = Path.Combine(Path.GetTempPath(), $"cai-additional-sym-work-{Guid.NewGuid():N}");
        Directory.CreateDirectory(sourceRoot);
        Directory.CreateDirectory(workspace);

        try
        {
            Directory.CreateDirectory(Path.Combine(sourceRoot, ".claude"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".claude", "settings.json"), "{}", TestContext.Current.CancellationToken);
            Directory.CreateDirectory(Path.Combine(sourceRoot, ".extra", "real"));
            await File.WriteAllTextAsync(Path.Combine(sourceRoot, ".extra", "real", "file.txt"), "value\n", TestContext.Current.CancellationToken);
            File.CreateSymbolicLink(
                Path.Combine(sourceRoot, ".extra", "link"),
                Path.Combine(sourceRoot, ".extra", "real"));

            var configPath = Path.Combine(workspace, "containai.toml");
            await File.WriteAllTextAsync(
                configPath,
                $$"""
                [agent]
                data_volume = "{{volume}}"

                [import]
                additional_paths = ["~/.extra/link"]
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new CaiCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(
                ["import", "--data-volume", volume, "--from", sourceRoot, "--workspace", workspace, "--config", configPath],
                TestContext.Current.CancellationToken);
            Assert.Equal(0, exitCode);
            Assert.Contains("contains symlink components", stderr.ToString(), StringComparison.Ordinal);

            var verify = await RunDockerAsync(
                ["run", "--rm", "-v", $"{volume}:/data", AlpineImage, "sh", "-lc", "set -eu; test ! -e /data/extra/link"],
                TestContext.Current.CancellationToken);
            Assert.Equal(0, verify.ExitCode);
        }
        finally
        {
            Directory.Delete(sourceRoot, recursive: true);
            Directory.Delete(workspace, recursive: true);
            _ = await RunDockerAsync(["volume", "rm", "-f", volume], TestContext.Current.CancellationToken);
        }
    }

    [Fact]
    public void ImportRuntimeSource_ContainsEnvGuardMessages()
    {
        var caiSourceDir = LocateRepositoryPath("src", "cai");
        var sourceBuilder = new StringBuilder();

        foreach (var importSourcePath in Directory.GetFiles(caiSourceDir, "CaiImportService.ImportEnvironment*.cs", SearchOption.TopDirectoryOnly))
        {
            sourceBuilder.AppendLine();
            sourceBuilder.Append(File.ReadAllText(importSourcePath));
        }

        foreach (var utilitySourcePath in Directory.GetFiles(caiSourceDir, "CaiRuntimeSupport.Utilities*.cs", SearchOption.TopDirectoryOnly))
        {
            sourceBuilder.AppendLine();
            sourceBuilder.Append(File.ReadAllText(utilitySourcePath));
        }

        var source = sourceBuilder.ToString();

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
        var version = await RunProcessAsync("docker", ["--version"], cancellationToken).ConfigureAwait(false);
        if (version.ExitCode != 0)
        {
            return false;
        }

        var info = await RunDockerAsync(["info"], cancellationToken).ConfigureAwait(false);
        return info.ExitCode == 0;
    }

    private static async Task<ProcessResult> RunDockerAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var context = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var dockerArgs = new List<string>();
        if (!string.IsNullOrWhiteSpace(context))
        {
            dockerArgs.Add("--context");
            dockerArgs.Add(context);
        }

        dockerArgs.AddRange(args);
        return await RunProcessAsync("docker", dockerArgs, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
    {
        var explicitContext = Environment.GetEnvironmentVariable("CONTAINAI_DOCKER_CONTEXT");
        if (!string.IsNullOrWhiteSpace(explicitContext))
        {
            return explicitContext;
        }

        var list = await RunProcessAsync("docker", ["context", "ls", "--format", "{{.Name}}"], cancellationToken).ConfigureAwait(false);
        if (list.ExitCode != 0)
        {
            return null;
        }

        var availableContexts = SplitNonEmptyLines(list.StandardOutput);
        foreach (var context in new[] { "containai-docker", "containai-secure", "docker-containai" })
        {
            if (availableContexts.Contains(context, StringComparer.Ordinal))
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
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);

            return new ProcessResult(
                process.ExitCode,
                await stdoutTask.ConfigureAwait(false),
                await stderrTask.ConfigureAwait(false));
        }
        catch (Win32Exception ex)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
        catch (InvalidOperationException ex)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
        catch (IOException ex)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
    }

    private sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError);
}
