defmodule LotteryApi.Cache do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def get(key) do
    case :ets.lookup(__MODULE__, key) do
      [{^key, value}] -> value
      _ -> nil
    end
  end

  def insert(object) do
    :ets.insert(__MODULE__, object)
  end

  def update(key, element) do
    :ets.update_element(__MODULE__, key, element)
  end

  @impl true
  def init(:ok) do
    opts = [:set, :public, :named_table, read_concurrency: true, write_concurrency: true]
    :ets.new(__MODULE__, opts)
    {:ok, :ok}
  end
end
