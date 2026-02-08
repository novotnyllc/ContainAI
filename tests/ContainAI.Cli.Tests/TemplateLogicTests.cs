using System.Security.Cryptography;
using System.Text;
using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class TemplateLogicTests
{
    [Fact]
    public void TemplateDirectory_UsesHomeConfigPath()
    {
        var homePath = "/tmp/home-test";
        Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", null);

        var path = TemplateUtilities.ResolveTemplatesDirectory(homePath);

        Assert.Equal(Path.Combine(homePath, ".config", "containai", "templates"), path);
    }

    [Fact]
    public void TemplateDirectory_UsesXdgConfigHomeWhenSet()
    {
        var xdg = Path.Combine(Path.GetTempPath(), $"xdg-{Guid.NewGuid():N}");
        Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", xdg);
        try
        {
            var path = TemplateUtilities.ResolveTemplatesDirectory("/unused/home");
            Assert.Equal(Path.Combine(xdg, "containai", "templates"), path);
        }
        finally
        {
            Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", null);
        }
    }

    [Fact]
    public void TemplatePath_ResolvesDefaultAndCustomNames()
    {
        var homePath = "/tmp/home-test";
        Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", null);

        Assert.Equal(
            Path.Combine(homePath, ".config", "containai", "templates", "default", "Dockerfile"),
            TemplateUtilities.ResolveTemplateDockerfilePath(homePath));

        Assert.Equal(
            Path.Combine(homePath, ".config", "containai", "templates", "my-custom-template", "Dockerfile"),
            TemplateUtilities.ResolveTemplateDockerfilePath(homePath, "my-custom-template"));
    }

    [Theory]
    [InlineData("default", true)]
    [InlineData("my-template", true)]
    [InlineData("template_v1", true)]
    [InlineData("template.1", true)]
    [InlineData("a1b2c3", true)]
    [InlineData("", false)]
    [InlineData("../etc", false)]
    [InlineData("a/b", false)]
    [InlineData("Template", false)]
    [InlineData("UPPER", false)]
    [InlineData("mixedCase", false)]
    [InlineData("in valid", false)]
    [InlineData("name@123", false)]
    [InlineData("_invalid", false)]
    [InlineData("-invalid", false)]
    [InlineData(".invalid", false)]
    public void TemplateNameValidation_MatchesRules(string templateName, bool expectedValid)
    {
        Assert.Equal(expectedValid, TemplateUtilities.IsValidTemplateName(templateName));
    }

    [Fact]
    public void TemplateFingerprint_ComputesSha256ForTemplateDockerfile()
    {
        const string dockerfile = "FROM ghcr.io/novotnyllc/containai:latest\nUSER agent\n";

        var actual = TemplateUtilities.ComputeTemplateFingerprint(dockerfile);

        var expected = ToLowerHex(Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(dockerfile))));
        Assert.Equal(expected, actual);
    }

    private static string ToLowerHex(string value)
        => string.Create(
            value.Length,
            value,
            static (chars, source) =>
            {
                for (var i = 0; i < source.Length; i++)
                {
                    chars[i] = char.ToLowerInvariant(source[i]);
                }
            });

    [Fact]
    public void TryUpgradeDockerfile_InjectsBaseImageArg()
    {
        const string source = "FROM ghcr.io/novotnyllc/containai:latest\nUSER agent\n";

        var changed = TemplateUtilities.TryUpgradeDockerfile(source, out var updated);

        Assert.True(changed);
        Assert.Contains("ARG BASE_IMAGE=ghcr.io/novotnyllc/containai:latest", updated, StringComparison.Ordinal);
        Assert.Contains("FROM ${BASE_IMAGE}", updated, StringComparison.Ordinal);
        Assert.Contains("USER agent", updated, StringComparison.Ordinal);
    }

    [Fact]
    public void TryUpgradeDockerfile_NoOpWhenAlreadyParameterized()
    {
        const string source = "ARG BASE_IMAGE=ghcr.io/novotnyllc/containai:latest\nFROM ${BASE_IMAGE}\n";

        var changed = TemplateUtilities.TryUpgradeDockerfile(source, out var updated);

        Assert.False(changed);
        Assert.Equal(source, updated);
    }
}
