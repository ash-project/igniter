defmodule Igniter.Util.Loading do
  @moduledoc """
  Utilities for doing operations with loading spinners.
  """

  @spinners "⠁⠂⠄⡀⡁⡂⡄⡅⡇⡏⡗⡧⣇⣏⣗⣧⣯⣷⣿⢿⣻⢻⢽⣹⢹⢸⠸⢘⠘⠨⢈⠈⠐⠠⢀" |> String.graphemes()

  @doc """
  Runs the function with a loading spinner, suppressing all output.
  """
  def with_spinner(name, fun, opts \\ []) do
    if opts[:verbose?] do
      Mix.shell().info(name <> ":")
      result = fun.()
      Mix.shell().info(name <> ": " <> "#{IO.ANSI.green()}✔#{IO.ANSI.reset()}")
      result
    else
      shell = Mix.shell()

      # I don't understand why I have to do this
      if !Code.ensure_loaded?(Mix.Shell.ActuallyQuiet) do
        Code.eval_quoted(
          quote do
            defmodule Mix.Shell.ActuallyQuiet do
              @moduledoc false
              @behaviour Mix.Shell

              def print_app, do: :ok

              def info(_message), do: :ok

              def error(_message), do: :ok

              def prompt(_message), do: :ok

              def yes?(_message, _options \\ []), do: :ok

              def cmd(command, opts \\ []) do
                Mix.Shell.cmd(command, opts, fn data -> data end)
              end
            end
          end
        )
      end

      {:ok, _} = Igniter.CaptureServer.start_link([])

      loader =
        if shell == Mix.Shell.IO do
          spawn_loader(name)
        end

      Mix.shell(Mix.Shell.ActuallyQuiet)

      {:ok, ref} =
        Igniter.CaptureServer.device_capture_on(:standard_error, :unicode, "")

      try do
        fun.()
      rescue
        e ->
          IO.puts(Igniter.CaptureServer.device_output(:standard_error, ref))
          reraise e, __STACKTRACE__
      after
        if shell == Mix.Shell.IO do
          loader_ref = make_ref()
          send(loader, {:stop, self(), loader_ref})

          receive do
            {:loader_stopped, ^loader_ref} ->
              nil
          after
            500 ->
              :ok
          end
        end

        Mix.shell(shell)
        Igniter.CaptureServer.device_capture_off(ref)
        GenServer.stop(Igniter.CaptureServer)
      end
    end
  end

  def spawn_loader(task_name) do
    spawn_link(fn ->
      @spinners
      |> Stream.cycle()
      |> Stream.map(fn next ->
        receive do
          {:stop, pid, ref} ->
            IO.puts("\r\e[K" <> task_name <> ": " <> "#{IO.ANSI.green()}✔#{IO.ANSI.reset()}")
            send(pid, {:loader_stopped, ref})
            exit(:normal)
        after
          0 ->
            IO.write("\r\e[K" <> task_name <> ": " <> next)
            :timer.sleep(50)
        end
      end)
      |> Stream.run()
    end)
  end
end
