defmodule NervesMCP.History do
  @moduledoc """
  Stores recent device output in a circular buffer.
  """

  use Agent

  @default_size 10_000

  def start_link(opts \\ []) do
    size = Keyword.get(opts, :size, @default_size)
    Agent.start_link(fn -> CircularBuffer.new(size) end, name: __MODULE__)
  end

  def push(data) when is_binary(data) do
    Agent.update(__MODULE__, fn buffer ->
      CircularBuffer.insert(buffer, {System.monotonic_time(), data})
    end)
  end

  def get do
    Agent.get(__MODULE__, fn buffer ->
      buffer
      |> CircularBuffer.to_list()
      |> Enum.map_join(fn {_ts, data} -> data end)
    end)
  end

  def clear do
    Agent.update(__MODULE__, fn buffer ->
      CircularBuffer.new(buffer.max_size)
    end)
  end
end
