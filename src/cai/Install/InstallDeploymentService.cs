namespace ContainAI.Cli.Host;

internal interface IInstallDeploymentService
{
    InstallDeploymentResult Deploy(string sourceExecutablePath, string installDir, string binDir);
}

internal sealed partial class InstallDeploymentService : IInstallDeploymentService
{
}

internal sealed record InstallDeploymentResult(
    string InstalledExecutablePath,
    string WrapperPath,
    string DockerProxyPath);
