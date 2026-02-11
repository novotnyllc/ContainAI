using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal interface ICaiDoctorTemplateValidator
{
    Task<bool> ResolveTemplateStatusAsync(bool buildTemplates, CancellationToken cancellationToken);
}

internal sealed class CaiDoctorTemplateValidator : ICaiDoctorTemplateValidator
{
    public Task<bool> ResolveTemplateStatusAsync(bool buildTemplates, CancellationToken cancellationToken)
        => buildTemplates
            ? ValidateTemplatesAsync(cancellationToken)
            : Task.FromResult(true);

    private static async Task<bool> ValidateTemplatesAsync(CancellationToken cancellationToken)
    {
        var templatesRoot = CaiRuntimeConfigRoot.ResolveTemplatesDirectory();
        if (!Directory.Exists(templatesRoot))
        {
            return false;
        }

        foreach (var dockerfile in Directory.EnumerateFiles(templatesRoot, "Dockerfile", SearchOption.AllDirectories))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var directory = Path.GetDirectoryName(dockerfile)!;
            var imageName = $"containai-template-check-{Path.GetFileName(directory)}";
            var build = await CaiRuntimeDockerHelpers
                .DockerCaptureAsync(["build", "-q", "-f", dockerfile, "-t", imageName, directory], cancellationToken)
                .ConfigureAwait(false);
            if (build.ExitCode != 0)
            {
                return false;
            }
        }

        return true;
    }
}
