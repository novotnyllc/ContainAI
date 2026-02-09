using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class ContainerLinkRepairServiceTests
{
    [Fact]
    public async Task RunAsync_CheckMode_ReturnsFailureWhenLinkMissing()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var docker = new FakeDockerExecutor
        {
            BuiltinSpecJson =
                """
                {
                  "links": [
                    { "link": "/home/agent/.config/tool", "target": "/mnt/agent-data/tool", "remove_first": false }
                  ]
                }
                """,
        };
        var service = new ContainerLinkRepairService(stdout, stderr, docker.ExecuteAsync);

        var exitCode = await service.RunAsync("workspace-main", ContainerLinkRepairMode.Check, quiet: false, TestContext.Current.CancellationToken);

        Assert.Equal(1, exitCode);
        Assert.Contains("[MISSING] /home/agent/.config/tool -> /mnt/agent-data/tool", stdout.ToString(), StringComparison.Ordinal);
        Assert.Contains("Missing:", stdout.ToString(), StringComparison.Ordinal);
        Assert.Equal(string.Empty, stderr.ToString());
    }

    [Fact]
    public async Task RunAsync_FixMode_ReplacesConflictingFileAndWritesTimestamp()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var docker = new FakeDockerExecutor
        {
            BuiltinSpecJson =
                """
                {
                  "links": [
                    { "link": "/home/agent/.config/tool", "target": "/mnt/agent-data/tool", "remove_first": false }
                  ]
                }
                """,
        };
        docker.Files.Add("/home/agent/.config/tool");
        docker.Directories.Add("/mnt/agent-data/tool");

        var service = new ContainerLinkRepairService(stdout, stderr, docker.ExecuteAsync);
        var exitCode = await service.RunAsync("workspace-main", ContainerLinkRepairMode.Fix, quiet: false, TestContext.Current.CancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Contains("/home/agent/.config/tool", docker.SymbolicLinks.Keys, StringComparer.Ordinal);
        Assert.Equal("/mnt/agent-data/tool", docker.SymbolicLinks["/home/agent/.config/tool"]);
        Assert.NotNull(docker.WrittenTimestamp);
        Assert.Matches("^[0-9]{14}$", docker.WrittenTimestamp!);
        Assert.Contains("[FIXED] /home/agent/.config/tool -> /mnt/agent-data/tool", stdout.ToString(), StringComparison.Ordinal);
        Assert.Contains("Updated links-checked-at timestamp", stdout.ToString(), StringComparison.Ordinal);
        Assert.Equal(string.Empty, stderr.ToString());
    }

    [Fact]
    public async Task RunAsync_DryRun_DoesNotMutateContainerState()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var docker = new FakeDockerExecutor
        {
            BuiltinSpecJson =
                """
                {
                  "links": [
                    { "link": "/home/agent/.config/tool", "target": "/mnt/agent-data/tool", "remove_first": false }
                  ]
                }
                """,
        };

        var service = new ContainerLinkRepairService(stdout, stderr, docker.ExecuteAsync);
        var exitCode = await service.RunAsync("workspace-main", ContainerLinkRepairMode.DryRun, quiet: false, TestContext.Current.CancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Empty(docker.SymbolicLinks);
        Assert.Null(docker.WrittenTimestamp);
        Assert.Contains("[WOULD] Create symlink: /home/agent/.config/tool -> /mnt/agent-data/tool", stdout.ToString(), StringComparison.Ordinal);
        Assert.Equal(string.Empty, stderr.ToString());
    }

    private sealed class FakeDockerExecutor
    {
        private const string BuiltinSpecPath = "/usr/local/lib/containai/link-spec.json";
        private const string UserSpecPath = "/mnt/agent-data/containai/user-link-spec.json";
        private const string CheckedAtPath = "/mnt/agent-data/.containai-links-checked-at";

        public required string BuiltinSpecJson { get; init; }

        public HashSet<string> Files { get; } = new(StringComparer.Ordinal);
        public HashSet<string> Directories { get; } = new(StringComparer.Ordinal);
        public Dictionary<string, string> SymbolicLinks { get; } = new(StringComparer.Ordinal);
        public string? WrittenTimestamp { get; private set; }

        public Task<CommandExecutionResult> ExecuteAsync(IReadOnlyList<string> arguments, string? standardInput, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Assert.True(arguments.Count >= 3, "docker command should include exec container command");
            Assert.Equal("exec", arguments[0]);

            var index = 1;
            if (string.Equals(arguments[index], "-i", StringComparison.Ordinal))
            {
                index++;
            }

            _ = arguments[index++];
            var command = arguments[index];

            return Task.FromResult(command switch
            {
                "cat" => HandleCat(arguments[index + 1]),
                "test" => HandleTest(arguments[index + 1], arguments[^1]),
                "readlink" => HandleReadLink(arguments[^1]),
                "mkdir" => HandleMkdir(arguments[^1]),
                "rm" => HandleRemove(arguments[^1]),
                "ln" => HandleLink(arguments[index + 3], arguments[index + 4]),
                "tee" => HandleTee(arguments[index + 1], standardInput),
                "chown" => Ok(),
                _ => Fail($"unsupported fake docker command '{command}'"),
            });
        }

        private CommandExecutionResult HandleCat(string path)
            => path switch
            {
                BuiltinSpecPath => Ok(BuiltinSpecJson),
                UserSpecPath => Fail("no such file or directory"),
                _ => Fail("no such file or directory"),
            };

        private CommandExecutionResult HandleTest(string testOption, string path)
        {
            var exists = testOption switch
            {
                "-L" => SymbolicLinks.ContainsKey(path),
                "-d" => Directories.Contains(path),
                "-f" => Files.Contains(path),
                "-e" => Exists(path),
                _ => false,
            };

            return exists ? Ok() : Fail();
        }

        private CommandExecutionResult HandleReadLink(string path)
            => SymbolicLinks.TryGetValue(path, out var target)
                ? Ok(target + Environment.NewLine)
                : Fail("invalid argument");

        private CommandExecutionResult HandleMkdir(string path)
        {
            Directories.Add(path);
            return Ok();
        }

        private CommandExecutionResult HandleRemove(string path)
        {
            Files.Remove(path);
            Directories.Remove(path);
            SymbolicLinks.Remove(path);
            return Ok();
        }

        private CommandExecutionResult HandleLink(string target, string link)
        {
            SymbolicLinks[link] = target;
            return Ok();
        }

        private CommandExecutionResult HandleTee(string path, string? standardInput)
        {
            if (!string.Equals(path, CheckedAtPath, StringComparison.Ordinal))
            {
                return Fail("unexpected tee target");
            }

            WrittenTimestamp = (standardInput ?? string.Empty).Trim();
            Files.Add(path);
            return Ok(standardInput ?? string.Empty);
        }

        private bool Exists(string path)
        {
            if (Files.Contains(path) || Directories.Contains(path))
            {
                return true;
            }

            if (!SymbolicLinks.TryGetValue(path, out var target))
            {
                return false;
            }

            return Files.Contains(target) || Directories.Contains(target) || SymbolicLinks.ContainsKey(target);
        }

        private static CommandExecutionResult Ok(string output = "")
            => new(0, output, string.Empty);

        private static CommandExecutionResult Fail(string error = "")
            => new(1, string.Empty, error);
    }
}
