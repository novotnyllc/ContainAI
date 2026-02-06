using ContainAI.Cli;
using ContainAI.Cli.Host;

var runtimeService = new CommandRuntimeService();
var runtime = new CaiCommandRuntime(runtimeService, new AcpProxyRunner());

return await CaiCli.RunAsync(args, runtime);
