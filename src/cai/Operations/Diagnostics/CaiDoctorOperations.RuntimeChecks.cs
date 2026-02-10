namespace ContainAI.Cli.Host;

internal sealed partial class CaiDoctorOperations
{
    private async Task<int?> TryResetLimaAsync(bool resetLima, CancellationToken cancellationToken)
    {
        if (!resetLima)
        {
            return null;
        }

        if (!OperatingSystem.IsMacOS())
        {
            await stderr.WriteLineAsync("--reset-lima is only available on macOS").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Resetting Lima VM containai...").ConfigureAwait(false);
        await RunProcessCaptureAsync("limactl", ["delete", "containai", "--force"], cancellationToken).ConfigureAwait(false);
        await RunProcessCaptureAsync("docker", ["context", "rm", "-f", "containai-docker"], cancellationToken).ConfigureAwait(false);
        return null;
    }

    private static List<string> BuildDockerInfoArgs(string? contextName, bool contextExists)
    {
        var dockerInfoArgs = new List<string>();
        if (contextExists)
        {
            dockerInfoArgs.Add("--context");
            dockerInfoArgs.Add(contextName!);
        }

        dockerInfoArgs.Add("info");
        return dockerInfoArgs;
    }

    private static Task<bool> ResolveTemplateStatusAsync(bool buildTemplates, CancellationToken cancellationToken) =>
        buildTemplates
            ? ValidateTemplatesAsync(cancellationToken)
            : Task.FromResult(true);

    private static async Task<bool> ValidateTemplatesAsync(CancellationToken cancellationToken)
    {
        var templatesRoot = ResolveTemplatesDirectory();
        if (!Directory.Exists(templatesRoot))
        {
            return false;
        }

        foreach (var dockerfile in Directory.EnumerateFiles(templatesRoot, "Dockerfile", SearchOption.AllDirectories))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var directory = Path.GetDirectoryName(dockerfile)!;
            var imageName = $"containai-template-check-{Path.GetFileName(directory)}";
            var build = await DockerCaptureAsync(["build", "-q", "-f", dockerfile, "-t", imageName, directory], cancellationToken).ConfigureAwait(false);
            if (build.ExitCode != 0)
            {
                return false;
            }
        }

        return true;
    }
}
