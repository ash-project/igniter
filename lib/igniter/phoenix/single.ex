if Code.ensure_loaded?(Phx.New.Project) do
  defmodule Igniter.Phoenix.Single do
    @moduledoc false
    # Wrap Phx.New.Single
    # https://github.com/phoenixframework/phoenix/blob/7586cbee9e37afbe0b3cdbd560b9e6aa60d32bf6/installer/lib/phx_new/single.ex

    alias Igniter.Phoenix.Generator
    alias Phx.New.Project

    @mod Phx.New.Single

    def generate(igniter, project) do
      generators = [
        {true, &gen_new/2},
        {Project.ecto?(project), &gen_ecto/2},
        {Project.html?(project), &gen_html/2},
        {Project.mailer?(project), &gen_mailer/2},
        {Project.gettext?(project), &gen_gettext/2},
        {true, &gen_assets/2}
      ]

      Enum.reduce(generators, igniter, fn
        {true, gen_fun}, acc -> gen_fun.(acc, project)
        _, acc -> acc
      end)
    end

    def gen_new(igniter, project) do
      Generator.copy_from(igniter, project, @mod, :new)
    end

    def gen_ecto(igniter, project) do
      igniter
      |> Generator.copy_from(project, @mod, :ecto)
      |> Generator.gen_ecto_config(project)
    end

    def gen_html(igniter, project) do
      Generator.copy_from(igniter, project, @mod, :html)
    end

    def gen_mailer(igniter, project) do
      Generator.copy_from(igniter, project, @mod, :mailer)
    end

    def gen_gettext(igniter, project) do
      Generator.copy_from(igniter, project, @mod, :gettext)
    end

    def gen_assets(igniter, project) do
      javascript? = Project.javascript?(project)
      css? = Project.css?(project)
      html? = Project.html?(project)

      igniter = Generator.copy_from(igniter, project, @mod, :static)

      igniter =
        if html? or javascript? do
          command = if javascript?, do: :js, else: :no_js
          Generator.copy_from(igniter, project, @mod, command)
        else
          igniter
        end

      if html? or css? do
        command = if css?, do: :css, else: :no_css
        Generator.copy_from(igniter, project, @mod, command)
      else
        igniter
      end
    end
  end
end
