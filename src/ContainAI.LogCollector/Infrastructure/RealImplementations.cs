using System.IO;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using ContainAI.LogCollector.Abstractions;

namespace ContainAI.LogCollector.Infrastructure;

public class RealFileSystem : IFileSystem
{
    public void CreateDirectory(string path) => Directory.CreateDirectory(path);
    public bool FileExists(string path) => File.Exists(path);
    public void DeleteFile(string path) => File.Delete(path);
    public Stream OpenAppend(string path) => new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.Read);
}

public class RealSocketProvider : ISocketProvider
{
    public ISocketListener Bind(string path)
    {
        var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        socket.Bind(new UnixDomainSocketEndPoint(path));
        socket.Listen();
        return new RealSocketListener(socket);
    }
}

public class RealSocketListener : ISocketListener
{
    private readonly Socket _socket;

    public RealSocketListener(Socket socket)
    {
        _socket = socket;
    }

    public async Task<Stream> AcceptAsync(CancellationToken token)
    {
        var client = await _socket.AcceptAsync(token);
        return new NetworkStream(client, ownsSocket: true);
    }

    public void Dispose()
    {
        _socket.Dispose();
    }
}
