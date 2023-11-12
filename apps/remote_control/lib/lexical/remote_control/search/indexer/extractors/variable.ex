defmodule Lexical.RemoteControl.Search.Indexer.Extractors.Variable do
  # alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  # alias Lexical.ProcessCache
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Metadata
  alias Lexical.RemoteControl.Search.Indexer.Source.Block
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  def extract(
        {:=, _aissignment_meta, [left, _right]} = elem,
        %Reducer{} = reducer
      ) do
    %Block{} = block = Reducer.current_block(reducer)
    subjet_with_ranges = left |> extract_from_left(reducer) |> List.wrap() |> List.flatten()

    entries =
      for {subject, range} <- subjet_with_ranges do
        Entry.definition(
          reducer.document.path,
          block.ref,
          block.parent_ref,
          subject,
          :variable,
          range,
          get_application(reducer.document)
        )
      end

    {:ok, entries, elem}
  end

  def extract({:def, _, definition}, %Reducer{} = reducer) do
    [function_header, _block] = definition
    {_function_name, _meta, params} = function_header

    %Block{} = block = Reducer.current_block(reducer)
    subjet_with_ranges = params |> List.wrap() |> extract_from_left(reducer) |> List.flatten()

    entries =
      for {subject, range} <- subjet_with_ranges do
        Entry.definition(
          reducer.document.path,
          block.ref,
          block.parent_ref,
          subject,
          :variable,
          range,
          get_application(reducer.document)
        )
      end

    {:ok, entries, definition}
  end

  def extract(
        _elem,
        %Reducer{} = _reducer
      ) do
    :ignored
  end

  defp extract_from_left({variable, meta, nil}, reducer) do
    range = to_range(reducer.document, variable, Metadata.position(meta))
    {variable, range}
  end

  defp extract_from_left(ast_list, reducer) when is_list(ast_list) do
    Enum.map(ast_list, fn ast -> extract_from_left(ast, reducer) end)
  end

  # def foo(a, `b \\ 2`)
  defp extract_from_left({:\\, _meta, [parameter, _default_value]}, reducer) do
    extract_from_left(parameter, reducer)
  end

  # `%{a: a, b: b}` = %{a: 1, b: 2}
  defp extract_from_left({:%{}, _map_metadata, fields}, reducer) do
    Enum.map(fields, fn {_key, value} -> extract_from_left(value, reducer) end)
  end

  # `%Foo{a: a, b: b}` = %Foo{a: 1, b: 2}
  defp extract_from_left({:%, _map_metadata, [_struct_module_info, struct_block]}, reducer) do
    # struct_block is the same as `%{a: a, b: b}`
    extract_from_left(struct_block, reducer)
  end

  # `[a, b]` = [1, 2]
  defp extract_from_left({:__block__, _, [block]}, reducer) when is_list(block) do
    extract_from_left(block, reducer)
  end

  # `{a, b}` = [1, 2]
  defp extract_from_left({:__block__, _, [block]}, reducer) when is_tuple(block) do
    block = Tuple.to_list(block)
    extract_from_left(block, reducer)
  end

  defp to_range(%Document{} = document, variable, {line, column}) do
    variable_length = variable |> to_string() |> String.length()

    Range.new(
      Position.new(document, line, column),
      Position.new(document, line, column + variable_length)
    )
  end

  defp get_application(_document) do
    # NOTE_TO_MYSELF: I think we should calculate the application name based on the path of the file
    # and find the nearest mix.exs file and use that as the application name
    nil
  end
end
