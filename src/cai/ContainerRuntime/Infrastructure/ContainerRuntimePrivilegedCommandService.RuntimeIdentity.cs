namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

internal sealed partial class ContainerRuntimePrivilegedCommandService
{
    private static bool IsRunningAsRoot()
    {
        try
        {
            return string.Equals(Environment.UserName, "root", StringComparison.Ordinal);
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (PlatformNotSupportedException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }
}
