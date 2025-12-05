using System.CommandLine;
using System.CommandLine.Parsing;
using ContainAI.LogCollector;
using ContainAI.LogCollector.Infrastructure;

class Program {
    static async Task<int> Main(string[] args) {
        var socketPathOption = new Option<string>(
            name: "--socket-path")
        {
            Description = "The path to the unix socket",
            DefaultValueFactory = (_) => "/run/containai/audit.sock"
        };

        var logDirOption = new Option<string>(
            name: "--log-dir")
        {
            Description = "The directory to write logs to",
            DefaultValueFactory = (_) => "/mnt/logs"
        };

        var root = new RootCommand("ContainAI Host Agent")
        {
            socketPathOption,
            logDirOption
        };
        
        root.SetAction(async (ParseResult result) => {
            var socketPath = result.GetValue(socketPathOption);
            var logDir = result.GetValue(logDirOption);
            
            Console.WriteLine($"Starting LogCollector with socket={socketPath}, logs={logDir}");
            
            var cts = new CancellationTokenSource();
            Console.CancelKeyPress += (s, e) => {
                e.Cancel = true;
                cts.Cancel();
            };

            var service = new LogCollectorService(
                socketPath!, 
                logDir!,
                new RealFileSystem(),
                new RealSocketProvider());
            try 
            {
                await service.RunAsync(cts.Token);
            }
            catch (OperationCanceledException)
            {
                Console.WriteLine("Stopping...");
            }
        });

        var parseResult = CommandLineParser.Parse(root, args);
        return await parseResult.InvokeAsync();
    }
}
