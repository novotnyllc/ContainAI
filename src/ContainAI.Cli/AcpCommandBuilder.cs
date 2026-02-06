using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal sealed class AcpCommandBuilder
{
    public Command Build(ICaiCommandRuntime runtime)
    {
        ArgumentNullException.ThrowIfNull(runtime);

        var acpCommand = new Command("acp", "ACP tooling");
        var proxyCommand = new Command("proxy", "Start ACP proxy for an agent");

        var agentArgument = new Argument<string>("agent")
        {
            Arity = ArgumentArity.ZeroOrOne,
            Description = "Agent binary name (defaults to claude)",
            DefaultValueFactory = _ => "claude",
        };

        proxyCommand.Arguments.Add(agentArgument);
        proxyCommand.SetAction((parseResult, cancellationToken) =>
        {
            var agent = parseResult.GetValue(agentArgument) ?? "claude";
            return runtime.RunAcpProxyAsync(agent, cancellationToken);
        });

        acpCommand.Subcommands.Add(proxyCommand);

        return acpCommand;
    }
}
