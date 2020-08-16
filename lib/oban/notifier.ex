defmodule Oban.Notifier do
  @moduledoc false

  alias Oban.Config

  @mappings %{
    gossip: "oban_gossip",
    insert: "oban_insert",
    signal: "oban_signal"
  }

  @channels Map.keys(@mappings)

  defmacro gossip, do: @mappings[:gossip]
  defmacro insert, do: @mappings[:insert]
  defmacro signal, do: @mappings[:signal]

  defmacro mappings, do: Macro.escape(@mappings)
  defmacro channels, do: @channels

  defguardp is_server(server) when is_pid(server) or is_atom(server)

  @spec listen(module()) :: :ok
  def listen(server, channels \\ @channels) when is_server(server) and is_list(channels) do
    GenServer.call(server, {:listen, channels})
  end

  @spec notify(Config.t(), binary(), map()) :: :ok
  def notify(%Config{notifier: notifier} = conf, channel, %{} = payload) when is_binary(channel) do
    notifier.notify(conf, channel, payload)
  end

end
