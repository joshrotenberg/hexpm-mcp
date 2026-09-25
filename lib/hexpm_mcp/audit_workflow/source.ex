defmodule HexpmMcp.AuditWorkflow.Source do
  @moduledoc """
  Bounded, revision-coalescing status stream over authoritative scoped snapshots.

  At most 32 task IDs are accepted. There is one pending pull, no accumulating
  event queue and no polling while the client applies backpressure. Every pull
  reauthorizes each inspected ID. Already-terminal tasks are emitted once then
  retired. Reconnect starts with current state, not historical events. Cancellation
  or close kills the source promptly, including a blocked database read/pull.
  """
  use GenServer
  @behaviour MCP.Subscription.Source

  alias MCP.Error
  alias MCP.Extensions.Tasks
  alias MCP.Extensions.Tasks.Store
  alias MCP.Extensions.Tasks.Task, as: ProtocolTask

  @max_tasks 32

  @impl MCP.Subscription.Source
  def open(filter, context, %{store: store, poll_interval_ms: interval})
      when is_integer(interval) and interval >= 10 and interval <= 60_000 do
    ids = Map.get(filter, "taskIds", [])

    if is_list(ids) and length(ids) in 1..@max_tasks and Enum.all?(ids, &is_binary/1) do
      {:ok, pid} =
        GenServer.start(__MODULE__, %{
          ids: Enum.uniq(ids),
          context: context,
          store: store,
          interval: interval,
          revisions: %{},
          waiter: nil,
          monitor: nil,
          timer: nil
        })

      {:ok, %{"taskIds" => Enum.uniq(ids)}, pid}
    else
      {:error, Error.invalid_params("Listen requires between 1 and #{@max_tasks} task IDs")}
    end
  end

  @impl MCP.Subscription.Source
  def next(pid, _options) do
    GenServer.call(pid, :next, :infinity)
  catch
    :exit, _reason -> :closed
  end

  @impl MCP.Subscription.Source
  def close(pid, _reason, _options) do
    # The source is unlinked and owns no external resources. Exit also interrupts
    # an in-flight DB checkout and immediately releases the blocked next/2 caller.
    Process.exit(pid, :shutdown)
    :ok
  end

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call(:next, {caller, _tag} = from, %{waiter: nil} = state) do
    pull(%{state | waiter: from, monitor: Process.monitor(caller)})
  end

  def handle_call(:next, _from, state),
    do: {:reply, {:error, :concurrent_pull}, state}

  @impl GenServer
  def handle_info(:poll, state), do: pull(%{state | timer: nil})

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}

  defp pull(state) do
    case changed_snapshot(state.ids, state) do
      {:event, event, next_state} ->
        {:noreply, reply(next_state, {:ok, event})}

      {:wait, %{ids: []} = next_state} ->
        {:stop, :normal, reply(next_state, :closed)}

      {:wait, next_state} ->
        timer = Process.send_after(self(), :poll, state.interval)
        {:noreply, %{next_state | timer: timer}}

      {:error, reason} ->
        {:stop, :normal, reply(state, {:error, reason})}
    end
  end

  defp reply(state, value) do
    # Source callers need not keep the same worker between pulls (e.g. Plug).
    # Monitor only the outstanding call, never a completed callback process.
    Process.demonitor(state.monitor, [:flush])
    GenServer.reply(state.waiter, value)
    %{state | waiter: nil, monitor: nil}
  end

  defp changed_snapshot([], state), do: {:wait, state}

  defp changed_snapshot([id | remaining], state) do
    with {:ok, access} <- Store.authorize(state.store, state.context, {:get, id}),
         {:ok, snapshot} <- Store.get(state.store, id, access) do
      if Map.get(state.revisions, id) == snapshot.revision do
        changed_snapshot(remaining, state)
      else
        ids = remaining_ids(state.ids, id, snapshot.task)

        next_state = %{
          state
          | ids: ids,
            revisions: Map.put(state.revisions, id, snapshot.revision)
        }

        {:event, Tasks.status_event(snapshot.task), next_state}
      end
    else
      absent when absent in [:not_found, {:error, :unauthorized}] ->
        changed_snapshot(remaining, %{state | ids: List.delete(state.ids, id)})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remaining_ids(ids, id, task) do
    remaining = List.delete(ids, id)
    if ProtocolTask.terminal?(task), do: remaining, else: remaining ++ [id]
  end
end
