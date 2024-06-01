defmodule Igniter.Application do
  @moduledoc "Codemods and tools for working with Application modules."

  def app_name do
    Mix.Project.config()[:app]
  end
end
