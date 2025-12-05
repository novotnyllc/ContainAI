namespace ContainAI.LogCollector.Abstractions;

public interface ISocketProvider
{
    ISocketListener Bind(string path);
}

public interface ISocketListener : IDisposable
{
    Task<Stream> AcceptAsync(CancellationToken token);
}
