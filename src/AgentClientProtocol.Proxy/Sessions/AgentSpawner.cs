// Agent process spawning using System.Diagnostics.Process
using System.ComponentModel;
using System.Diagnostics;
using System.Text;

namespace AgentClientProtocol.Proxy.Sessions;

/// <summary>
/// Spawns agent processes for ACP sessions.
/// </summary>
public sealed class AgentSpawner : IAgentSpawner
{
    private static readonly UTF8Encoding Utf8NoBom = new(encoderShouldEmitUTF8Identifier: false);
    private readonly bool _directSpawn;
    private readonly TextWriter _stderr;
    private readonly string _caiExecutable;

    /// <summary>
    /// Creates a new agent spawner.
    /// </summary>
    /// <param name="directSpawn">If true, spawns the agent directly; otherwise wraps with cai exec.</param>
    /// <param name="stderr">Stream to forward agent stderr to.</param>
    /// <param name="caiExecutable">ContainAI executable path used for container-side execution.</param>
    public AgentSpawner(bool directSpawn, TextWriter stderr, string caiExecutable = "cai")
    {
        _directSpawn = directSpawn;
        _stderr = stderr;
        _caiExecutable = caiExecutable;
    }

    /// <summary>
    /// Spawns an agent process for a session.
    /// Sets up stdin/stdout pipes and starts the stderr forwarding task.
    /// </summary>
    /// <param name="session">The session to spawn the agent for.</param>
    /// <param name="agent">The agent binary name (any agent supporting --acp flag).</param>
    /// <returns>The spawned process.</returns>
    /// <exception cref="InvalidOperationException">
    /// Thrown when the agent binary cannot be found or started.
    /// </exception>
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
                StandardInputEncoding = Utf8NoBom,
                StandardOutputEncoding = Utf8NoBom,
                StandardErrorEncoding = Utf8NoBom,
            };
            psi.ArgumentList.Add("--acp");

            try
            {
                process = Process.Start(psi);
            }
            catch (Win32Exception ex)
            {
                // Binary not found or not executable
                throw new InvalidOperationException(
                    $"Agent '{agent}' not found. Ensure the agent binary is installed and in PATH.",
                    ex);
            }
        }
        else
        {
            // Container-side preflight check: wrap the agent command to detect missing binaries
            // and provide a clear error message. Agent is passed as a positional parameter ($1)
            // to avoid shell injection risks.
            //
            // The wrapper script:
            // 1. Checks if the agent binary exists in the container (command -v)
            // 2. If not found, prints a clear error and exits with code 127
            // 3. If found, exec's the agent with --acp
            var psi = new ProcessStartInfo
            {
                FileName = _caiExecutable,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                StandardInputEncoding = Utf8NoBom,
                StandardOutputEncoding = Utf8NoBom,
                StandardErrorEncoding = Utf8NoBom,
            };
            // Use ArgumentList to safely pass arguments without quoting issues
            psi.ArgumentList.Add("exec");
            psi.ArgumentList.Add("--workspace");
            psi.ArgumentList.Add(session.Workspace);
            psi.ArgumentList.Add("--quiet");
            psi.ArgumentList.Add("--");
            psi.ArgumentList.Add("bash");
            // Use -c (not -lc) to avoid login shell sourcing profile files that could
            // emit output to stdout and corrupt the ACP JSON-RPC stream
            psi.ArgumentList.Add("-c");
            // Safe: agent passed as $1, not interpolated into shell string
            // Use 'exec --' to safely handle agent names that start with '-'
            psi.ArgumentList.Add("command -v -- \"$1\" >/dev/null 2>&1 || { printf \"Agent '%s' not found in container\\n\" \"$1\" >&2; exit 127; }; exec -- \"$1\" --acp");
            psi.ArgumentList.Add("--");  // End of bash -c options
            psi.ArgumentList.Add(agent); // $1 for the script

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
            catch (Exception ex)
            {
                _ = _stderr.WriteLineAsync($"Failed to forward agent stderr: {ex.Message}");
            }
        });

        return process;
    }
}
