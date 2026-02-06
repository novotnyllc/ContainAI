using ContainAI.Cli;
using ContainAI.Cli.Host;

var runtime = new CaiCommandRuntime(new AcpProxyRunner());

return await CaiCli.RunAsync(args, runtime);
