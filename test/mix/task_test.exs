defmodule Igniter.Mix.TaskTest do
  use ExUnit.Case

  defmodule ExampleTask do
    use Igniter.Mix.Task

    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        schema: [
          option: :string
        ],
        positional: [
          :a,
          b: [
            optional: true,
            rest: true
          ]
        ]
      }
    end

    def igniter(igniter, argv) do
      options = options!(argv)
      {args, _argv} = positional_args!(argv)

      send(self(), {:args, args})
      send(self(), {:options, options})
      igniter
    end
  end

  test "it parses options" do
    ExampleTask.igniter(Igniter.new(), ["foo", "--option", "foo"])
    assert_received {:options, options}
    assert options[:option] == "foo"
    assert_received {:args, %{a: "foo"}}
  end

  test "it parses rest options" do
    ExampleTask.igniter(Igniter.new(), ["foo", "--option", "foo"])
    assert_received {:options, options}
    assert options[:option] == "foo"
    assert_received {:args, %{a: "foo"}}
  end
end
