namespace ContainAI.Cli.Host;

internal interface IInstallDeploymentService
{
    InstallDeploymentResult Deploy(string sourceExecutablePath, string installDir, string binDir);
}
