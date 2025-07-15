for {task_name, config} <- Igniter.Installer.TaskHelpers.tasks() do
  if !Code.ensure_loaded?(config.module) do
    defmodule config.module do
      use Mix.Task

      @moduledoc Igniter.Installer.TaskHelpers.long_doc(task_name)
      @impl true
      @shortdoc Igniter.Installer.TaskHelpers.short_doc(task_name)
      def run(argv) do
        Igniter.Installer.TaskHelpers.wrap_task(
          unquote(task_name),
          unquote(Macro.escape(config.mfa)),
          argv
        )
      end
    end
  end
end
