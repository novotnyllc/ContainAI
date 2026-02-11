namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerProcessExecution
{
    public bool IsProcessAlive(int processId)
    {
        if (processId <= 0)
        {
            return false;
        }

        try
        {
            if (OperatingSystem.IsLinux() && fileSystem.DirectoryExists($"/proc/{processId}"))
            {
                return true;
            }

            if (OperatingSystem.IsLinux() || OperatingSystem.IsMacOS())
            {
                var result = processCaptureRunner
                    .RunCaptureAsync("kill", ["-0", processId.ToString(System.Globalization.CultureInfo.InvariantCulture)], CancellationToken.None)
                    .GetAwaiter()
                    .GetResult();
                return result.ExitCode == 0;
            }
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (IOException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }

        return false;
    }
}
