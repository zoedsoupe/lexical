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
  require Logger

  def extract(
        {:=, _assignment_meta, [left, _right]} = elem,
        %Reducer{} = reducer
      ) do
    subject_with_ranges = left |> extract_from_left(reducer) |> List.wrap() |> List.flatten()
    entries = to_definition_entries(subject_with_ranges, reducer)
    {:ok, entries, elem}
  end

  def extract({:def, _, definition} = elem, %Reducer{} = reducer) do
    [function_header, _block] = definition
    {_function_name, _meta, params} = function_header
    params = List.wrap(params)

    subject_with_ranges = [
      extract_from_left(params, reducer) ++ extract_from_right(params, reducer)
    ]

    entries = to_definition_entries(subject_with_ranges, reducer)
    {:ok, entries, elem}
  end

  def extract({variable_atom, meta, nil}, %Reducer{} = reducer) when is_atom(variable_atom) do
    position = {line, column} = Metadata.position(meta)

    case find_definition(reducer, variable_atom) do
      nil ->
        Logger.error("Variable definition not found for #{variable_atom} at #{inspect(position)}")
        :ignored

      %Entry{range: %Range{start: %Position{line: definition_line, character: definition_char}}}
      when definition_line == line and definition_char == column ->
        # That means current position is the `definition`
        :ignored

      definition ->
        {:ok,
         Entry.reference(
           reducer.document.path,
           make_ref(),
           definition.ref,
           variable_atom,
           :variable,
           to_range(reducer.document, variable_atom, position),
           get_application(reducer.document)
         )}
    end
  end

  def extract(
        _elem,
        %Reducer{} = _reducer
      ) do
    :ignored
  end

  defp find_definition(reducer, variable_atom) do
    block_parent_links =
      Map.new(reducer.blocks, fn block -> {block.ref, block.parent_ref} end)

    current_block = Reducer.current_block(reducer)

    current_block_ancestors =
      current_block.ref
      |> block_ancestors(block_parent_links, [current_block.ref])
      |> MapSet.new()

    Enum.find(reducer.entries, fn entry ->
      entry.type == :variable and
        entry.subtype == :definition and
        entry.subject == variable_atom and MapSet.member?(current_block_ancestors, entry.parent)
    end)
  end

  defp block_ancestors(block_ref, block_parent_links, acc) do
    root_ref = Block.root().ref

    case Map.get(block_parent_links, block_ref) do
      nil ->
        acc

      ^root_ref ->
        [root_ref | acc]

      parent_ref ->
        block_ancestors(parent_ref, block_parent_links, [parent_ref | acc])
    end
  end

  defp to_definition_entries(subject_with_ranges, reducer) do
    %Block{} = block = Reducer.current_block(reducer)

    for {subject, range} <- List.flatten(subject_with_ranges) do
      Entry.definition(
        reducer.document.path,
        make_ref(),
        block.ref,
        subject,
        :variable,
        range,
        get_application(reducer.document)
      )
    end
  end

  defp do_extract({variable, meta, nil}, reducer) do
    range = to_range(reducer.document, variable, Metadata.position(meta))
    {variable, range}
  end

  # like params: def foo«(1 = a, 2 = b)»
  defp extract_from_right(ast_list, reducer) when is_list(ast_list) do
    Enum.map(ast_list, fn ast -> extract_from_right(ast, reducer) end)
  end

  # pattern matching: def foo(a, «1 = b») do
  defp extract_from_right({:=, _meta, [_left, right]}, reducer) do
    do_extract(right, reducer)
  end

  defp extract_from_right(_, _) do
    []
  end

  # «a» = 1
  defp extract_from_left({_variable, _meta, nil} = elem, reducer) do
    do_extract(elem, reducer)
  end

  # like: [«a, b»] = [1, 2] or {«a, b»} = [1, 2]
  defp extract_from_left(ast_list, reducer) when is_list(ast_list) do
    Enum.map(ast_list, fn ast -> extract_from_left(ast, reducer) end)
  end

  # def foo(a, «b \\ 2»)
  defp extract_from_left({:\\, _meta, [parameter, _default_value]}, reducer) do
    extract_from_left(parameter, reducer)
  end

  # «%{a: a, b: b}» = %{a: 1, b: 2}
  defp extract_from_left({:%{}, _map_metadata, fields}, reducer) do
    Enum.map(fields, fn {_key, value} -> extract_from_left(value, reducer) end)
  end

  # «%Foo{a: a, b: b}» = %Foo{a: 1, b: 2}
  defp extract_from_left({:%, _map_metadata, [_struct_module_info, struct_block]}, reducer) do
    # struct_block is the same as «%{a: a, b: b}»
    extract_from_left(struct_block, reducer)
  end

  # «[a, b]» = [1, 2]
  defp extract_from_left({:__block__, _, [block]}, reducer) when is_list(block) do
    extract_from_left(block, reducer)
  end

  # «{a, b}» = [1, 2]
  defp extract_from_left({:__block__, _, [block]}, reducer) when is_tuple(block) do
    block = Tuple.to_list(block)
    extract_from_left(block, reducer)
  end

  defp extract_from_left(_, _reducer) do
    []
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
