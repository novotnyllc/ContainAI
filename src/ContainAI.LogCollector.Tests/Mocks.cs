using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;
using ContainAI.LogCollector.Abstractions;

namespace ContainAI.LogCollector.Tests;

public class MockFileSystem : IFileSystem
{
    public List<string> CreatedDirectories { get; } = new();
    public List<string> DeletedFiles { get; } = new();
    public Dictionary<string, MemoryStream> Files { get; } = new();

    public void CreateDirectory(string path)
    {
        CreatedDirectories.Add(path);
    }

    public void DeleteFile(string path)
    {
        DeletedFiles.Add(path);
        if (Files.ContainsKey(path))
        {
            Files.Remove(path);
        }
    }

    public bool FileExists(string path)
    {
        return Files.ContainsKey(path);
    }

    public Stream OpenAppend(string path)
    {
        if (!Files.TryGetValue(path, out var stream))
        {
            stream = new MemoryStream();
            Files[path] = stream;
        }
        return new NonClosingStreamWrapper(stream);
    }
}

public class NonClosingStreamWrapper : Stream
{
    private readonly Stream _inner;

    public NonClosingStreamWrapper(Stream inner)
    {
        _inner = inner;
    }

    public override bool CanRead => _inner.CanRead;
    public override bool CanSeek => _inner.CanSeek;
    public override bool CanWrite => _inner.CanWrite;
    public override long Length => _inner.Length;
    public override long Position { get => _inner.Position; set => _inner.Position = value; }

    public override void Flush() => _inner.Flush();
    public override int Read(byte[] buffer, int offset, int count) => _inner.Read(buffer, offset, count);
    public override long Seek(long offset, SeekOrigin origin) => _inner.Seek(offset, origin);
    public override void SetLength(long value) => _inner.SetLength(value);
    public override void Write(byte[] buffer, int offset, int count) => _inner.Write(buffer, offset, count);
    
    // Do not close the inner stream
    protected override void Dispose(bool disposing) { }
}

public class MockSocketProvider : ISocketProvider
{
    public MockSocketListener Listener { get; } = new();
    public string? BoundPath { get; private set; }

    public ISocketListener Bind(string path)
    {
        BoundPath = path;
        return Listener;
    }
}

public class MockSocketListener : ISocketListener
{
    private readonly Channel<Stream> _connections = Channel.CreateUnbounded<Stream>();
    public bool IsDisposed { get; private set; }

    public async Task<Stream> AcceptAsync(CancellationToken cancellationToken)
    {
        return await _connections.Reader.ReadAsync(cancellationToken);
    }

    public void Dispose()
    {
        IsDisposed = true;
    }

    public void SimulateConnection(string data)
    {
        var stream = new MemoryStream(Encoding.UTF8.GetBytes(data + "\n"));
        _connections.Writer.TryWrite(stream);
    }
}
