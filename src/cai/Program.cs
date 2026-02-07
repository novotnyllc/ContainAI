using ContainAI.Cli;
using ContainAI.Cli.Host;

var invocationName = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]);
if (string.Equals(invocationName, "containai-docker", StringComparison.OrdinalIgnoreCase))
{
    return await ContainAiDockerProxy.RunAsync(args, Console.Out, Console.Error, CancellationToken.None);
}

var runtime = new CaiCommandRuntime(new AcpProxyRunner());

return await CaiCli.RunAsync(args, runtime);
