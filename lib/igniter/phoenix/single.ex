# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Phx.New.Project) do
  defmodule Igniter.Phoenix.Single do
    @moduledoc false
    # Wrap Phx.New.Single
    # https://github.com/phoenixframework/phoenix/blob/7586cbee9e37afbe0b3cdbd560b9e6aa60d32bf6/installer/lib/phx_new/single.ex

    alias Igniter.Phoenix.Generator

    @mod Phx.New.Single

    def generate(igniter, project) do
      igniter = gen_new(igniter, project)

      igniter =
        if Keyword.get(project.binding, :ecto, false) do
          gen_ecto(igniter, project)
        else
          igniter
        end

      igniter =
        if Keyword.get(project.binding, :html, false) do
          gen_html(igniter, project)
        else
          igniter
        end

      igniter =
        if Keyword.get(project.binding, :mailer, false) do
          gen_mailer(igniter, project)
        else
          igniter
        end

      igniter =
        if Keyword.get(project.binding, :gettext, false) do
          gen_gettext(igniter, project)
        else
          igniter
        end

      gen_assets(igniter, project)
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
      javascript? = Keyword.get(project.binding, :javascript, false)
      css? = Keyword.get(project.binding, :css, false)
      html? = Keyword.get(project.binding, :html, false)

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
