if Code.ensure_loaded?(Phoenix.PubSub) do
  defmodule Oban.Notifier.PhoenixPubSub do
    @moduledoc false

    use GenServer

    import Oban.Notifier, only: [mappings: 0, channels: 0, gossip: 0, insert: 0, signal: 0]

    alias Oban.Config
    alias Phoenix.PubSub

    @type option :: {:name, module()} | {:conf, Config.t()}
    @type channel :: :gossip | :insert | :signal
    @type queue :: atom()

    defmodule State do
      @moduledoc false

      @enforce_keys [:conf]
      defstruct [
        :conf,
        :name,
        subscribed: false,
        listeners: %{}
      ]
    end

    defguardp is_server(server) when is_pid(server) or is_atom(server)

    @spec start_link([option]) :: GenServer.on_start()
    def start_link(opts) do
      name = Keyword.get(opts, :name, Oban.Notifier)

      GenServer.start_link(__MODULE__, Map.new(opts), name: name)
    end

    @spec listen(module()) :: :ok
    def listen(server, channels \\ channels()) when is_server(server) and is_list(channels) do
      GenServer.call(server, {:listen, channels})
    end

    @spec notify(Config.t(), binary(), map()) :: :ok
    def notify(%Config{pubsub: pubsub}, channel, %{} = payload) when is_binary(channel) do
      PubSub.broadcast(pubsub, channel, {:notification, channel, payload})
    end

    @impl GenServer
    def init(opts) do
      Process.flag(:trap_exit, true)

      {:ok, struct!(State, opts), {:continue, :start}}
    end

    @impl GenServer
    def handle_continue(:start, state) do
      {:noreply, subscribe(state)}
    end

    @impl GenServer
    def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{listeners: listeners} = state) do
      {:noreply, %{state | listeners: Map.delete(listeners, pid)}}
    end

    def handle_info({:notification, channel, payload}, state) do
      for {pid, channels} <- state.listeners, channel in channels do
        send(pid, {:notification, channel, payload})
      end

      {:noreply, state}
    end

    def handle_info(_message, state) do
      {:noreply, state}
    end

    @impl GenServer
    def handle_call({:listen, channels}, {pid, _}, %State{listeners: listeners} = state) do
      if Map.has_key?(listeners, pid) do
        {:reply, :ok, state}
      else
        Process.monitor(pid)

        full_channels =
          mappings()
          |> Map.take(channels)
          |> Map.values()

        {:reply, :ok, %{state | listeners: Map.put(listeners, pid, full_channels)}}
      end
    end

    defp subscribe(%State{subscribed: false, conf: conf} = state) do
      PubSub.subscribe(conf.pubsub, gossip())
      PubSub.subscribe(conf.pubsub, insert())
      PubSub.subscribe(conf.pubsub, signal())

      %{state | subscribed: true}
    end

    defp subscribe(state), do: state
  end
end
