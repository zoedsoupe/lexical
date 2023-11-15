defmodule Lexical.RemoteControl.Search.Indexer.Metadata do
  @moduledoc """
  Utilities for extracting location information from AST metadata nodes.
  """

  # def location({:->, meta, [left, {:__block__, right_meta, right_blocks}]}) do
  #   block_start = arrow_block_start(left)
  #
  #   if pos = position(right_meta) do
  #     block_end = pos
  #     {:block, position(meta), block_start, block_end}
  #   else
  #     {_, last_meta, _} = List.last(right_blocks)
  #     block_end = position(last_meta, :end_of_expression)
  #     {:block, position(meta), block_start, block_end}
  #   end
  # end
  #
  def location({_, metadata, _}) do
    if Keyword.has_key?(metadata, :do) do
      position = position(metadata)
      block_start = position(metadata, :do)
      block_end = position(metadata, :end_of_expression) || position(metadata, :end)
      {:block, position, block_start, block_end}
    else
      {:expression, position(metadata)}
    end
  end

  def location(_unknown) do
    {:expression, nil}
  end

  def position(keyword) do
    line = Keyword.get(keyword, :line)
    column = Keyword.get(keyword, :column)

    case {line, column} do
      {nil, nil} ->
        nil

      position ->
        position
    end
  end

  def position(keyword, key) do
    keyword
    |> Keyword.get(key, [])
    |> position()
  end

  defp arrow_block_start({_, meta, nil}) do
    position(meta)
  end

  defp arrow_block_start({_, _meta, block_list}) when is_list(block_list) do
    [{_, meta, blocks} | _] = block_list

    if blocks == [] do
      position(meta)
    else
      arrow_block_start(blocks)
    end
  end

  defp arrow_block_start([{_, _, _} = first_elem | _] = _left) do
    arrow_block_start(first_elem)
  end
end
