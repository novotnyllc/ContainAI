namespace ContainAI.Cli.Host;

internal interface ICaiUpdateUsageWriter
{
    Task<int> WriteUpdateUsageAsync();
}
