# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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

              def error(message) do
                # Instead of discarding, send to stderr so it gets captured
                IO.puts(:stderr, message)
                :ok
              end

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

      try do
        Mix.shell(Mix.Shell.ActuallyQuiet)

        {:ok, ref} =
          Igniter.CaptureServer.device_capture_on(:standard_error, :unicode, "")

        try do
          with_log(fn ->
            do_with_io(self(), [], fn ->
              fun.()
            end)
            |> elem(0)
          end)
          |> elem(0)
        catch
          kind, reason ->
            Process.put(:spinner_error, true)
            Mix.shell(shell)
            Mix.shell().info(Igniter.CaptureServer.device_output(:standard_error, ref))
            :erlang.raise(kind, reason, __STACKTRACE__)
        after
          Mix.shell(shell)
          Igniter.CaptureServer.device_capture_off(ref)
          GenServer.stop(Igniter.CaptureServer)
        end
      after
        if shell == Mix.Shell.IO do
          loader_ref = make_ref()
          error_occurred = Process.get(:spinner_error, false)

          stop_message =
            if error_occurred,
              do: {:stop_error, self(), loader_ref},
              else: {:stop_success, self(), loader_ref}

          send(loader, stop_message)

          receive do
            {:loader_stopped, ^loader_ref} ->
              nil
          after
            500 ->
              :ok
          end
        end
      end
    end
  end

  defp do_with_io(pid, options, fun) when is_pid(pid) do
    prompt_config = Keyword.get(options, :capture_prompt, true)
    encoding = Keyword.get(options, :encoding, :unicode)
    input = Keyword.get(options, :input, "")

    {:group_leader, original_gl} =
      Process.info(pid, :group_leader) || {:group_leader, Process.group_leader()}

    {:ok, capture_gl} = StringIO.open(input, capture_prompt: prompt_config, encoding: encoding)

    try do
      Process.group_leader(pid, capture_gl)
      do_capture_gl(capture_gl, fun)
    after
      Process.group_leader(pid, original_gl)
    end
  end

  defp do_capture_gl(string_io, fun) do
    fun.()
  catch
    kind, reason ->
      _ = StringIO.close(string_io)
      :erlang.raise(kind, reason, __STACKTRACE__)
  else
    result ->
      {:ok, {_input, output}} = StringIO.close(string_io)
      {result, output}
  end

  def spawn_loader(task_name) do
    spawn_link(fn ->
      @spinners
      |> Stream.cycle()
      |> Stream.map(fn next ->
        receive do
          {:stop_success, pid, ref} ->
            IO.puts("\r\e[K" <> task_name <> " " <> "#{IO.ANSI.green()}✔#{IO.ANSI.reset()}")
            send(pid, {:loader_stopped, ref})
            exit(:normal)

          {:stop_error, pid, ref} ->
            IO.puts("\r\e[K" <> task_name <> " " <> "#{IO.ANSI.red()}✗#{IO.ANSI.reset()}")
            send(pid, {:loader_stopped, ref})
            exit(:normal)
        after
          0 ->
            IO.write("\r\e[K" <> task_name <> " " <> next)
            :timer.sleep(50)
        end
      end)
      |> Stream.run()
    end)
  end

  def with_log(opts \\ [], fun) when is_list(opts) do
    opts =
      if opts[:level] == :warn do
        IO.warn("level: :warn is deprecated, please use :warning instead")
        Keyword.put(opts, :level, :warning)
      else
        opts
      end

    {:ok, string_io} = StringIO.open("")

    try do
      ref = Igniter.CaptureServer.log_capture_on(self(), string_io, opts)

      try do
        fun.()
      after
        :ok = Logger.flush()
        :ok = Igniter.CaptureServer.log_capture_off(ref)
      end
    catch
      kind, reason ->
        _ = StringIO.close(string_io)
        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      result ->
        {:ok, {_input, output}} = StringIO.close(string_io)
        {result, output}
    end
  end
end
