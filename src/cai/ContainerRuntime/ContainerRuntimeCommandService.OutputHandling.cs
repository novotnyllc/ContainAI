using System.Text.Json;

namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

internal static class ContainerRuntimeExceptionHandling
{
    public static bool IsHandled(Exception exception)
        => exception is InvalidOperationException
            or IOException
            or UnauthorizedAccessException
            or JsonException
            or ArgumentException
            or NotSupportedException;
}
