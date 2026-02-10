namespace ContainAI.Cli.Host;

internal sealed partial class InstallDeploymentService
{
    public InstallDeploymentResult Deploy(string sourceExecutablePath, string installDir, string binDir)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceExecutablePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(installDir);
        ArgumentException.ThrowIfNullOrWhiteSpace(binDir);

        if (!File.Exists(sourceExecutablePath))
        {
            throw new FileNotFoundException("Source executable was not found.", sourceExecutablePath);
        }

        Directory.CreateDirectory(installDir);
        Directory.CreateDirectory(binDir);

        var installedExecutablePath = Path.Combine(installDir, "cai");
        File.Copy(sourceExecutablePath, installedExecutablePath, overwrite: true);
        EnsureExecutable(installedExecutablePath);

        var wrapperPath = Path.Combine(binDir, "cai");
        CreateExecutableLink(installedExecutablePath, wrapperPath);

        var dockerProxyPath = Path.Combine(binDir, "containai-docker");
        CreateExecutableLink(installedExecutablePath, dockerProxyPath);

        return new InstallDeploymentResult(installedExecutablePath, wrapperPath, dockerProxyPath);
    }
}
