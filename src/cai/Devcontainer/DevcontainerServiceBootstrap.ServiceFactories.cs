namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerServiceBootstrap
{
    private static DevcontainerSysboxVerificationService CreateSysboxVerificationService(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        TextWriter standardError)
    {
        ArgumentNullException.ThrowIfNull(processHelpers);
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        return new DevcontainerSysboxVerificationService(processHelpers, standardOutput, standardError);
    }

    private static DevcontainerSshdStartupService CreateSshdStartupService(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        TextWriter standardError,
        Func<string, string?> environmentVariableReader)
    {
        ArgumentNullException.ThrowIfNull(processHelpers);
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(environmentVariableReader);
        return new DevcontainerSshdStartupService(processHelpers, standardOutput, standardError, environmentVariableReader);
    }

    private static DevcontainerDockerdStartupService CreateDockerdStartupService(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        TextWriter standardError)
    {
        ArgumentNullException.ThrowIfNull(processHelpers);
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        return new DevcontainerDockerdStartupService(processHelpers, standardOutput, standardError);
    }
}
