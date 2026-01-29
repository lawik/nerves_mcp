defmodule NervesMCP.Connection.SSH do
  @moduledoc """
  Handles SSH connection to a Nerves device.

  Uses the system SSH command to connect and evaluate Elixir code.
  """

  def eval(code, config, timeout) do
    host = Keyword.fetch!(config, :host)
    user = Keyword.get(config, :user, "root")
    port = Keyword.get(config, :port, 22)

    # Escape the code for shell
    escaped_code = escape_for_shell(code <> "\n")

    # Build SSH command
    ssh_args = [
      "-o",
      "StrictHostKeyChecking=no",
      "-o",
      "UserKnownHostsFile=/dev/null",
      "-o",
      "ConnectTimeout=#{div(timeout, 1000)}",
      "-p",
      "#{port}",
      "#{user}@#{host}"
    ]

    case System.shell("echo #{escaped_code} | ssh #{Enum.join(ssh_args, " ")}", stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {output, _exit_code} ->
        {:error, "SSH command failed: #{String.trim(output)}"}
    end
  rescue
    e ->
      {:error, "SSH error: #{Exception.message(e)}"}
  end

  defp escape_for_shell(code) do
    # Single quote escape for shell
    escaped = String.replace(code, "'", "'\"'\"'")
    "'#{escaped}'"
  end
end
