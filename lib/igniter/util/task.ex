defmodule Igniter.Util.Task do
  @moduledoc "Utilities for running tasks"

  @spinners "⠁⠂⠄⡀⡁⡂⡄⡅⡇⡏⡗⡧⣇⣏⣗⣧⣯⣷⣿⢿⣻⢻⢽⣹⢹⢸⠸⢘⠘⠨⢈⠈⠐⠠⢀" |> String.graphemes()

  @doc "Runs a mix task with a loading spinner, quieting the output"
  def run_with_spinner(task_name, argv \\ []) do
    require Logger
    :ok = :logger.remove_handler(:default)

    :ok =
      :logger.add_handler(:default, :logger_std_h, %{
        config: %{type: {:device, Owl.LiveScreen}},
        formatter: Logger.Formatter.new()
      })

    Owl.LiveScreen.add_block(:dependency,
      state: :init,
      render: fn
        :init -> "init..."
        dependency -> ["dependency: ", Owl.Data.tag(dependency, :yellow)]
      end
    )

    Owl.LiveScreen.add_block(:compiling,
      render: fn
        :init -> "init..."
        filename -> ["compiling: ", Owl.Data.tag(to_string(filename), :cyan)]
      end
    )

    ["ecto", "phoenix", "ex_doc", "broadway"]
    |> Enum.each(fn dependency ->
      Owl.LiveScreen.update(:dependency, dependency)

      1..5
      |> Enum.map(&"filename#{&1}.ex")
      |> Enum.each(fn filename ->
        Owl.LiveScreen.update(:compiling, filename)
        Process.sleep(1000)
        Logger.debug("#{filename} compiled for dependency #{dependency}")
      end)
    end)

    Application.ensure_all_started(:owl)
    shell = Mix.shell()

    try do
      Mix.shell(Mix.Shell.Quiet)

      Mix.shell().info("mix #{task_name}")

      Owl.Spinner.run(
        fn ->
          Mix.Task.run(task_name, argv)

          :ok
        end,
        labels: [ok: "Done", error: "Failed", processing: "Please wait..."]
      )
    after
      Mix.shell(shell)
    end
  end

  def spawn_loader(task_name, shell) do
    spawn_link(fn ->
      @spinners
      |> Stream.cycle()
      |> Stream.map(fn next ->
        shell.info("\r\e[2C\e[K" <> task_name <> ": " <> next)
        :timer.sleep(50)
      end)
      |> Stream.run()
    end)
  end
end
