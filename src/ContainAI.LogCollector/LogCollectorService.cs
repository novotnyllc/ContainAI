using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;
using ContainAI.Protocol;
using ContainAI.LogCollector.Abstractions;

namespace ContainAI.LogCollector;

public class LogCollectorService
{
    private readonly string _socketPath;
    private readonly string _logDir;
    private readonly IFileSystem _fileSystem;
    private readonly ISocketProvider _socketProvider;

    public LogCollectorService(
        string socketPath, 
        string logDir,
        IFileSystem fileSystem,
        ISocketProvider socketProvider)
    {
        _socketPath = socketPath;
        _logDir = logDir;
        _fileSystem = fileSystem;
        _socketProvider = socketProvider;
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        var sessionId = Environment.GetEnvironmentVariable("CONTAINAI_SESSION_ID") ?? Guid.NewGuid().ToString();
        var logFile = Path.Combine(_logDir, $"session-{sessionId}.jsonl");

        _fileSystem.CreateDirectory(Path.GetDirectoryName(_socketPath)!);
        _fileSystem.CreateDirectory(_logDir);

        if (_fileSystem.FileExists(_socketPath))
        {
            _fileSystem.DeleteFile(_socketPath);
        }

        using var listener = _socketProvider.Bind(_socketPath);

        Console.WriteLine($"Listening on {_socketPath}");
        Console.WriteLine($"Writing logs to {logFile}");

        var channel = Channel.CreateUnbounded<AuditEvent>();

        // Writer Task
        var writerTask = Task.Run(async () =>
        {
            using var stream = _fileSystem.OpenAppend(logFile);
            using var writer = new StreamWriter(stream) { AutoFlush = true };
            await foreach (var evt in channel.Reader.ReadAllAsync(cancellationToken))
            {
                var json = JsonSerializer.Serialize(evt, AuditContext.Default.AuditEvent);
                await writer.WriteLineAsync(json);
            }
        }, cancellationToken);

        // Accept Loop
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                try
                {
                    var stream = await listener.AcceptAsync(cancellationToken);
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            using (stream)
                            using (var reader = new StreamReader(stream))
                            {
                                while (await reader.ReadLineAsync(cancellationToken) is { } line)
                                {
                                    if (string.IsNullOrWhiteSpace(line)) continue;
                                    
                                    try 
                                    {
                                        var evt = JsonSerializer.Deserialize(line, AuditContext.Default.AuditEvent);
                                        if (evt != null)
                                        {
                                            await channel.Writer.WriteAsync(evt, cancellationToken);
                                        }
                                    }
                                    catch (JsonException) 
                                    {
                                        // Ignore malformed lines
                                    }
                                }
                            }
                        }
                        catch (Exception ex) when (ex is not OperationCanceledException)
                        {
                            Console.Error.WriteLine($"Client error: {ex.Message}");
                        }
                    }, cancellationToken);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"Accept error: {ex.Message}");
                }
            }
        }
        finally
        {
            if (_fileSystem.FileExists(_socketPath))
            {
                _fileSystem.DeleteFile(_socketPath);
            }
        }
    }
}

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower)]
[JsonSerializable(typeof(AuditEvent))]
public partial class AuditContext : JsonSerializerContext {}
