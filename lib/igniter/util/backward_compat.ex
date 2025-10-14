# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Util.BackwardsCompat do
  @moduledoc "Contains functions that we need to use that were introduced in newer Elixir versions."

  if Version.match?(System.version(), ">= 1.16.0") do
    defdelegate relative_to_cwd(path, opts \\ []), to: Path
  else
    @doc """
    Convenience to get the path relative to the current working
    directory.

    If, for some reason, the current working directory
    cannot be retrieved, this function returns the given `path`.

    Check `relative_to/3` for the supported options.
    """
    @spec relative_to_cwd(Path.t(), keyword) :: binary
    def relative_to_cwd(path, opts \\ []) when is_list(opts) do
      case :file.get_cwd() do
        {:ok, base} -> relative_to(path, IO.chardata_to_string(base), opts)
        _ -> path
      end
    end

    @doc """
    Returns the direct relative path from `path` in relation to `cwd`.

    In other words, this function attempts to return a path such that
    `Path.expand(result, cwd)` points to `path`. This function aims
    to return a relative path whenever possible, but that's not guaranteed:

      * If both paths are relative, a relative path is always returned

      * If both paths are absolute, a relative path may be returned if
        they share a common prefix. You can pass the `:force` option to
        force this function to traverse up, but even then a relative
        path is not guaranteed (for example, if the absolute paths
        belong to different drives on Windows)

      * If a mixture of paths are given, the result will always match
        the given `path` (the first argument)

    This function expands `.` and `..` entries without traversing the
    file system, so it assumes no symlinks between the paths. See
    `safe_relative_to/2` for a safer alternative.

    ## Options

      * `:force` - (boolean since v1.16.0) if `true` forces a relative
      path to be returned by traversing the path up. Except if the paths
      are in different volumes on Windows. Defaults to `false`.

    ## Examples

    ### With relative `cwd`

    If both paths are relative, a minimum path is computed:

        Path.relative_to("tmp/foo/bar", "tmp")      #=> "foo/bar"
        Path.relative_to("tmp/foo/bar", "tmp/foo")  #=> "bar"
        Path.relative_to("tmp/foo/bar", "tmp/bat")  #=> "../foo/bar"

    If an absolute path is given with relative `cwd`, it is returned as:

        Path.relative_to("/usr/foo/bar", "tmp/bat")  #=> "/usr/foo/bar"

    ### With absolute `cwd`

    If both paths are absolute, a relative is computed if possible,
    without traversing up:

        Path.relative_to("/usr/local/foo", "/usr/local")      #=> "foo"
        Path.relative_to("/usr/local/foo", "/")               #=> "usr/local/foo"
        Path.relative_to("/usr/local/foo", "/etc")            #=> "/usr/local/foo"
        Path.relative_to("/usr/local/foo", "/usr/local/foo")  #=> "."
        Path.relative_to("/usr/local/../foo", "/usr/foo")     #=> "."
        Path.relative_to("/usr/local/../foo/bar", "/usr/foo") #=> "bar"

    If `:force` is set to `true` paths are traversed up:

        Path.relative_to("/usr", "/usr/local", force: true)          #=> ".."
        Path.relative_to("/usr/foo", "/usr/local", force: true)      #=> "../foo"
        Path.relative_to("/usr/../foo/bar", "/etc/foo", force: true) #=> "../../foo/bar"

    If a relative path is given, it is assumed to be relative to the
    given path, so the path is returned with "." and ".." expanded:

        Path.relative_to(".", "/usr/local")          #=> "."
        Path.relative_to("foo", "/usr/local")        #=> "foo"
        Path.relative_to("foo/../bar", "/usr/local") #=> "bar"
        Path.relative_to("foo/..", "/usr/local")     #=> "."
        Path.relative_to("../foo", "/usr/local")     #=> "../foo"

    """
    @spec relative_to(Path.t(), Path.t(), keyword) :: binary
    def relative_to(path, cwd, opts \\ []) when is_list(opts) do
      os_type = major_os_type()
      split_path = Path.split(path)
      split_cwd = Path.split(cwd)
      force = Keyword.get(opts, :force, false)

      case {split_absolute?(split_path, os_type), split_absolute?(split_cwd, os_type)} do
        {true, true} ->
          split_path = expand_split(split_path)
          split_cwd = expand_split(split_cwd)

          case force do
            true -> relative_to_forced(split_path, split_cwd, split_path)
            false -> relative_to_unforced(split_path, split_cwd, split_path)
          end

        {false, false} ->
          split_path = expand_relative(split_path, [], [])
          split_cwd = expand_relative(split_cwd, [], [])
          relative_to_forced(split_path, split_cwd, [])

        {_, _} ->
          Path.join(expand_relative(split_path, [], []))
      end
    end

    defp expand_relative([".." | t], [_ | acc], up), do: expand_relative(t, acc, up)
    defp expand_relative([".." | t], acc, up), do: expand_relative(t, acc, [".." | up])
    defp expand_relative(["." | t], acc, up), do: expand_relative(t, acc, up)
    defp expand_relative([h | t], acc, up), do: expand_relative(t, [h | acc], up)
    defp expand_relative([], [], []), do: ["."]
    defp expand_relative([], acc, up), do: up ++ :lists.reverse(acc)

    defp expand_split([head | tail]), do: expand_split(tail, [head])
    defp expand_split([".." | t], [_, last | acc]), do: expand_split(t, [last | acc])
    defp expand_split([".." | t], acc), do: expand_split(t, acc)
    defp expand_split(["." | t], acc), do: expand_split(t, acc)
    defp expand_split([h | t], acc), do: expand_split(t, [h | acc])
    defp expand_split([], acc), do: :lists.reverse(acc)

    defp split_absolute?(split, :win32), do: win32_split_absolute?(split)
    defp split_absolute?(split, _), do: match?(["/" | _], split)

    defp win32_split_absolute?(["//" | _]), do: true
    defp win32_split_absolute?([<<_, ":/">> | _]), do: true
    defp win32_split_absolute?(_), do: false
    defp relative_to_unforced(path, path, _original), do: "."

    defp relative_to_unforced([h | t1], [h | t2], original),
      do: relative_to_unforced(t1, t2, original)

    defp relative_to_unforced([_ | _] = l1, [], _original), do: Path.join(l1)
    defp relative_to_unforced(_, _, original), do: Path.join(original)

    defp relative_to_forced(path, path, _original), do: "."
    defp relative_to_forced(["."], _path, _original), do: "."
    defp relative_to_forced(path, ["."], _original), do: Path.join(path)

    defp relative_to_forced([h | t1], [h | t2], original),
      do: relative_to_forced(t1, t2, original)

    # this should only happen if we have two paths on different drives on windows
    defp relative_to_forced(original, _, original), do: Path.join(original)

    defp relative_to_forced(l1, l2, _original) do
      base = List.duplicate("..", length(l2))
      Path.join(base ++ l1)
    end

    defp major_os_type do
      :os.type() |> elem(0)
    end
  end
end
