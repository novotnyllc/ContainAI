using System.CommandLine;

var rootCommand = new RootCommand("ContainAI Host CLI");

rootCommand.SetHandler(() =>
{
    Console.WriteLine("ContainAI Host CLI");
});

return await rootCommand.InvokeAsync(args);
