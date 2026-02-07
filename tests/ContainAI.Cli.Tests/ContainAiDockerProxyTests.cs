using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class ContainAiDockerProxyTests
{
    [Fact]
    public void StripJsoncComments_RemovesLineAndBlockComments()
    {
        const string input = """
                             {
                               // line comment
                               "value": 1, /* block */
                               "nested": {
                                 "url": "https://example.com"
                               }
                             }
                             """;

        var output = ContainAiDockerProxy.StripJsoncComments(input);

        Assert.DoesNotContain("line comment", output, StringComparison.Ordinal);
        Assert.DoesNotContain("block", output, StringComparison.Ordinal);
        Assert.Contains("https://example.com", output, StringComparison.Ordinal);
    }

    [Fact]
    public void ExtractDevcontainerLabels_ReadsKnownLabels()
    {
        var (configFile, localFolder) = ContainAiDockerProxy.ExtractDevcontainerLabels(
        [
            "run",
            "--label",
            "devcontainer.config_file=/path/.devcontainer/devcontainer.json",
            "--label",
            "devcontainer.local_folder=/workspace/project",
        ]);

        Assert.Equal("/path/.devcontainer/devcontainer.json", configFile);
        Assert.Equal("/workspace/project", localFolder);
    }

    [Theory]
    [InlineData(new[] { "run", "alpine" }, true)]
    [InlineData(new[] { "create", "alpine" }, true)]
    [InlineData(new[] { "container", "run", "alpine" }, true)]
    [InlineData(new[] { "container", "create", "alpine" }, true)]
    [InlineData(new[] { "ps" }, false)]
    [InlineData(new[] { "exec", "demo", "sh" }, false)]
    public void IsContainerCreateCommand_ClassifiesSubcommands(string[] args, bool expected)
    {
        var actual = ContainAiDockerProxy.IsContainerCreateCommand(args);
        Assert.Equal(expected, actual);
    }

    [Theory]
    [InlineData("my-project", "my-project")]
    [InlineData("my project name", "my-project-name")]
    [InlineData("project@2024!test", "project-2024-test")]
    [InlineData("___", "___")]
    [InlineData("", "workspace")]
    public void SanitizeWorkspaceName_RewritesUnsafeCharacters(string input, string expected)
    {
        var output = ContainAiDockerProxy.SanitizeWorkspaceName(input);
        Assert.Equal(expected, output);
    }

    [Fact]
    public void TryReadFeatureSettings_ParsesContainAiFeatureJsonc()
    {
        using var temp = new TempDirectory();
        var filePath = Path.Combine(temp.Path, "devcontainer.json");
        File.WriteAllText(
            filePath,
            """
            {
              // comment
              "remoteUser": "agent",
              "features": {
                "ghcr.io/novotnyllc/containai/feature:latest": {
                  "dataVolume": "my-volume",
                  "enableCredentials": true
                }
              }
            }
            """);

        var success = ContainAiDockerProxy.TryReadFeatureSettings(filePath, TextWriter.Null, out var settings);

        Assert.True(success);
        Assert.True(settings.HasContainAiFeature);
        Assert.Equal("my-volume", settings.DataVolume);
        Assert.True(settings.EnableCredentials);
        Assert.Equal("agent", settings.RemoteUser);
    }

    [Fact]
    public void TryReadFeatureSettings_RejectsInvalidVolumeName()
    {
        using var temp = new TempDirectory();
        var filePath = Path.Combine(temp.Path, "devcontainer.json");
        File.WriteAllText(
            filePath,
            """
            {
              "features": {
                "ghcr.io/novotnyllc/containai/feature:latest": {
                  "dataVolume": "/etc/passwd"
                }
              }
            }
            """);

        var success = ContainAiDockerProxy.TryReadFeatureSettings(filePath, TextWriter.Null, out var settings);

        Assert.True(success);
        Assert.True(settings.HasContainAiFeature);
        Assert.Equal("containai-data", settings.DataVolume);
        Assert.False(settings.EnableCredentials);
        Assert.Equal("vscode", settings.RemoteUser);
    }

    [Theory]
    [InlineData("my-volume", true)]
    [InlineData("volume.with.dots", true)]
    [InlineData("host:container", false)]
    [InlineData("/tmp/path", false)]
    [InlineData("~", false)]
    public void IsValidVolumeName_ValidatesDockerVolumeName(string value, bool expected)
    {
        Assert.Equal(expected, ContainAiDockerProxy.IsValidVolumeName(value));
    }

    private sealed class TempDirectory : IDisposable
    {
        public TempDirectory()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"containai-proxy-tests-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            Directory.Delete(Path, recursive: true);
        }
    }
}
