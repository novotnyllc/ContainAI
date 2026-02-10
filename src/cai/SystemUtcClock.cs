namespace ContainAI.Cli.Host;

internal sealed class SystemUtcClock : IUtcClock
{
    public DateTime UtcNow => DateTime.UtcNow;
}
