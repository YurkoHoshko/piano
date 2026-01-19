defmodule PianoTest do
  use ExUnit.Case

  test "piano module exists" do
    assert is_list(Piano.module_info())
  end
end
