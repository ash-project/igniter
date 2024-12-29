defmodule Igniter.Installer.Task do
  @moduledoc false

  @spinners "⠁⠂⠄⡀⡁⡂⡄⡅⡇⡏⡗⡧⣇⣏⣗⣧⣯⣷⣿⢿⣻⢻⢽⣹⢹⢸⠸⢘⠘⠨⢈⠈⠐⠠⢀" |> String.graphemes()

  @doc "Runs a mix task with a loading spinner, quieting the output"
  def run_with_spinner(task_name, argv \\ []) do
    raise "WHAT"
    shell = Mix.shell()

    Mix.shell(Mix.Shell.Quiet)

    pid = spawn_loader(task_name, shell)

    try do
      Mix.Task.run(task_name, argv)
    after
      Mix.shell(shell)
      Process.exit(pid, :normal)
    end
  end

  def spawn_loader(task_name, shell) do
    spawn_link(fn ->
      @spinners
      |> Stream.cycle()
      |> Stream.map(fn next ->
        shell.info(task_name <> ": " <> next)
        :timer.sleep(50)
      end)
      |> Stream.run()
    end)
  end
end
