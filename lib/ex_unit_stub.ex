defmodule ExUnit do
  @moduledoc """
  Minimal ExUnit stub for Wallaby compatibility in production.

  Wallaby requires ExUnit for its session management callbacks.
  This module provides just enough functionality to satisfy Wallaby
  without including the full test framework in production.
  """

  @doc """
  Registers a callback to be run after the test suite completes.
  In production, this is a no-op since we don't have test suites.
  """
  def after_suite(callback) when is_function(callback, 1) do
    # In production, we don't have test suites, so this is a no-op
    # The callback would normally receive test results
    :ok
  end

  @doc """
  Stub for ExUnit configuration - returns empty config.
  """
  def configuration do
    %{}
  end

  @doc """
  Stub for ExUnit start - returns :ok since we're in production.
  """
  def start(_opts \\ []) do
    {:ok, self()}
  end
end
