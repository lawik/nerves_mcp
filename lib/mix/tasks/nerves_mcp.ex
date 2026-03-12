defmodule Mix.Tasks.NervesMcp do
  @moduledoc """
  Starts the NervesMCP server connected to a Nerves device.

  ## Examples

      mix nerves_mcp /dev/ttyUSB0
      mix nerves_mcp nerves.local --user root
      mix nerves_mcp --serial /dev/ttyACM0 --speed 9600
      mix nerves_mcp --ssh 192.168.1.100 --port 4000

  See `NervesMCP.CLI` for all options.
  """

  use Mix.Task

  @shortdoc "Start NervesMCP server connected to a device"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    NervesMCP.CLI.run(args)
    NervesMCP.CLI.repl()
  end
end
