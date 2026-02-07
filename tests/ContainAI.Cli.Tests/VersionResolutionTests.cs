using System.Reflection;
using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class VersionResolutionTests
{
    [Fact]
    public void ResolvesVersionFromAssemblyMetadata()
    {
        var expected = Assembly.GetEntryAssembly()?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
            ?? Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
            ?? Assembly.GetEntryAssembly()?.GetName().Version?.ToString()
            ?? Assembly.GetExecutingAssembly().GetName().Version?.ToString()
            ?? "0.0.0";

        var version = InstallMetadata.ResolveVersion();
        Assert.Equal(expected, version);
    }

    [Fact]
    public void ResolveInstallType_LocalPath_IsLocal()
    {
        var installDir = Path.Combine("/tmp", ".local", "share", "containai");
        var installType = InstallMetadata.ResolveInstallType(installDir);
        Assert.Equal(InstallType.Local, installType);
    }
}
