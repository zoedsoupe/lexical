defmodule Lexical.RemoteControl.Search.Indexer.Extractors.VariableTest do
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer
  alias Lexical.Test.RangeSupport

  import Lexical.Test.CodeSigil
  import RangeSupport

  use ExUnit.Case, async: true

  def index(source) do
    path = "/foo/bar/baz.ex"
    doc = Document.new("file:///#{path}", source, 1)

    case Indexer.Source.index("/foo/bar/baz.ex", source) do
      {:ok, indexed_items} -> {:ok, indexed_items, doc}
      error -> error
    end
  end

  describe "indexing definition of variable assignment" do
    test "simple assignment" do
      {:ok, [variable], doc} = ~q[
        a = 1
      ] |> index()

      assert variable.type == :variable
      assert variable.subject == :a
      assert variable.subtype == :definition

      assert decorate(doc, variable.range) =~ "«a» = 1"
    end

    test "multiple assignments with `Tuple` in one line" do
      {:ok, [a, b], doc} = ~q[
        {a, b} = {1, 2}
      ] |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "{«a», b}"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "{a, «b»}"
    end

    test "multiple assignments with `tuple` in multiple lines" do
      {:ok, [a, b], doc} = ~q[
        {a,
         b} =
          {1, 2}
      ] |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "{«a»,"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "«b»}"
    end

    test "multiple assignments with `list`" do
      {:ok, [a, b], doc} = ~q(
        [a, b] = [1, 2]
      ) |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "[«a», b]"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "[a, «b»]"
    end

    test "nested assignments" do
      {:ok, [a, b], doc} = ~q(
        {a, [b]} = {1, [2]}
      ) |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "{«a», [b]}"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "{a, [«b»]}"
    end

    test "multiple assignments with `map`" do
      {:ok, [foo, bar], doc} = ~q(
        %{foo: foo, bar: bar} = %{foo: 1, bar: 2}
      ) |> index()

      assert foo.subject == :foo
      assert decorate(doc, foo.range) =~ "%{foo: «foo», bar: bar}"

      assert bar.subject == :bar
      assert decorate(doc, bar.range) =~ "%{foo: foo, bar: «bar»}"
    end

    test "nested assignments with `map`" do
      {:ok, [foo, sub_foo], doc} = ~q(
      %{foo: foo, bar: %{sub_foo: sub_foo}} = %{foo: 1, bar: %{sub_foo: 2, sub_bar: 3}}
      ) |> index()

      assert foo.subject == :foo

      assert decorate(doc, foo.range) =~
               "%{foo: «foo», bar: %{sub_foo: sub_foo}}"

      assert sub_foo.subject == :sub_foo

      assert decorate(doc, sub_foo.range) =~
               "%{foo: foo, bar: %{sub_foo: «sub_foo»}}"
    end

    test "assignment with `struct`" do
      {:ok, [foo, _module_ref, _], doc} = ~q(
        %Foo{foo: foo} = %Foo{foo: 1, bar: 2}
      ) |> index()

      assert foo.subject == :foo
      assert decorate(doc, foo.range) =~ "%Foo{foo: «foo»}"
    end

    test "assignment with current module's `struct`"
  end

  describe "indexing assignments in the function" do
    test "no assignments in the parameter list" do
      assert {:ok, [], _doc} = ~q[
        def foo do
        end
      ] |> index()
    end

    test "simple assignment in the block" do
      {:ok, [variable], doc} = ~q[
        def foo do
          a = 1
        end
      ] |> index()

      assert variable.type == :variable
      assert variable.subject == :a
      assert decorate(doc, variable.range) =~ "«a» = 1"
    end

    test "in parameter list" do
      {:ok, [a, b], doc} = ~q[
        def foo(a, b) do
        end
      ] |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "def foo(«a», b)"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "def foo(a, «b»)"
    end

    test "in parameter list with default value" do
      {:ok, [a, b], doc} = ~q[
        def foo(a, b \\ 2) do
        end
      ] |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "def foo(«a», b \\\\ 2)"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "def foo(a, «b» \\\\ 2)"
    end

    test "in parameter list but on the right side" do
      {:ok, [a], doc} = ~q[
        def foo(:a = a, 1 = b) do
        end
      ] |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "def foo(1 = «a»)"
    end
  end
end
