namespace ContainAI.Cli.Host.Sessions.Infrastructure;

internal static class SessionRuntimeVolumeNameGenerator
{
    internal static string GenerateWorkspaceVolumeName(string workspace)
    {
        var repo = SessionRuntimeTextHelpers.SanitizeNameComponent(
            Path.GetFileName(Path.TrimEndingDirectorySeparator(workspace)),
            "workspace");
        var branch = "nogit";
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyyMMddHHmmss");

        try
        {
            var result = CliWrapProcessRunner
                .RunCaptureAsync(
                    "git",
                    ["-C", workspace, "rev-parse", "--abbrev-ref", "HEAD"],
                    CancellationToken.None)
                .WaitAsync(TimeSpan.FromSeconds(2))
                .GetAwaiter()
                .GetResult();

            if (result.ExitCode == 0)
            {
                var branchValue = result.StandardOutput.Trim();
                if (!string.IsNullOrWhiteSpace(branchValue))
                {
                    branch = SessionRuntimeTextHelpers.SanitizeNameComponent(
                        branchValue.Split('/').LastOrDefault() ?? branchValue,
                        "nogit");
                }
            }
        }
        catch (InvalidOperationException)
        {
            branch = "nogit";
        }
        catch (IOException)
        {
            branch = "nogit";
        }
        catch (TimeoutException)
        {
            branch = "nogit";
        }

        return $"{repo}-{branch}-{timestamp}";
    }
}
