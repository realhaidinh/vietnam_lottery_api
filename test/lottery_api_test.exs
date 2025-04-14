defmodule LotteryApiTest do
  use ExUnit.Case
  doctest LotteryApi

  test "greets the world" do
    assert LotteryApi.hello() == :world
  end
end
