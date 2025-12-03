using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace ContainAI.LogCollector.Abstractions;

public interface ISocketProvider
{
    ISocketListener Bind(string path);
}

public interface ISocketListener : IDisposable
{
    Task<Stream> AcceptAsync(CancellationToken token);
}
