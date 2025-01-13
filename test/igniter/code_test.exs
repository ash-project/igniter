defmodule Igniter.CodeTest do
  use ExUnit.Case, async: true
  doctest Igniter.Code

  describe "to_code/1" do
    test "logs a deprecated notice for strings" do
      logged =
        ExUnit.CaptureLog.capture_log(fn ->
          Igniter.Code.to_code("string")
        end)

      assert logged =~ "Implicit parsing of strings of code is deprecated."
      assert logged =~ "Instead of:\n\n    \"string\""
      assert logged =~ "You should write:\n\n    Igniter.Code.from_string!(\"string\")"
    end

    test "logs a deprecated notice for code tuples" do
      logged =
        ExUnit.CaptureLog.capture_log(fn ->
          Igniter.Code.to_code({:code, :quoted_form})
        end)

      assert logged =~ "Specifying quoted forms using :code tuples is deprecated."
      assert logged =~ "Instead of:\n\n    {:code, :quoted_form}"
      assert logged =~ "You should write:\n\n    Igniter.Code.quoted!(:quoted_form)"
    end

    test "does not log for code structs" do
      logged =
        ExUnit.CaptureLog.capture_log(fn ->
          Igniter.Code.to_code(%Igniter.Code{ast: :quoted_form})
        end)

      assert logged == ""
    end
  end
end
