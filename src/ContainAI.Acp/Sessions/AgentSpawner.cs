// Agent process spawning using System.Diagnostics.Process
using System.Diagnostics;

namespace ContainAI.Acp.Sessions;

/// <summary>
/// Spawns agent processes for ACP sessions.
/// </summary>
public sealed class AgentSpawner
{
    private readonly bool _directSpawn;
    private readonly TextWriter _stderr;

    /// <summary>
    /// Creates a new agent spawner.
    /// </summary>
    /// <param name="directSpawn">If true, spawns the agent directly; otherwise wraps with cai exec.</param>
    /// <param name="stderr">Stream to forward agent stderr to.</param>
    public AgentSpawner(bool directSpawn, TextWriter stderr)
    {
        _directSpawn = directSpawn;
        _stderr = stderr;
    }

    /// <summary>
    /// Spawns an agent process for a session.
    /// Sets up stdin/stdout pipes and starts the stderr forwarding task.
    /// </summary>
    /// <param name="session">The session to spawn the agent for.</param>
    /// <param name="agent">The agent name (e.g., "claude", "gemini").</param>
    /// <returns>The spawned process.</returns>
    public Process SpawnAgent(AcpSession session, string agent)
    {
        Process? process;
        if (_directSpawn)
        {
            var psi = new ProcessStartInfo
            {
                FileName = agent,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            psi.ArgumentList.Add("--acp");
            process = Process.Start(psi);
        }
        else
        {
            var psi = new ProcessStartInfo
            {
                FileName = "cai",
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            // Use ArgumentList to safely pass arguments without quoting issues
            psi.ArgumentList.Add("exec");
            psi.ArgumentList.Add("--workspace");
            psi.ArgumentList.Add(session.Workspace);
            psi.ArgumentList.Add("--quiet");
            psi.ArgumentList.Add("--");
            psi.ArgumentList.Add(agent);
            psi.ArgumentList.Add("--acp");

            // Prevent stdout pollution from child cai processes
            psi.Environment["CAI_NO_UPDATE_CHECK"] = "1";

            process = Process.Start(psi);
        }

        if (process == null)
        {
            throw new InvalidOperationException($"Failed to start agent process: {agent}");
        }

        // Forward stderr to our stderr
        _ = Task.Run(async () =>
        {
            try
            {
                var errReader = process.StandardError;
                string? line;
                while ((line = await errReader.ReadLineAsync()) != null)
                {
                    await _stderr.WriteLineAsync(line);
                }
            }
            catch
            {
                // Ignore errors during stderr forwarding
            }
        });

        return process;
    }
}
