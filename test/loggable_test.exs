defmodule StathamLogger.LoggableTest do
  use ExUnit.Case, async: true

  alias StathamLogger.{Loggable, JasonEncodableStruct}

  defmodule SimpleStruct do
    defstruct [:name, :password, :not_loaded_assoc]
  end

  describe "hides sensitive data" do
    test """
    - long strings: shortened
    - keyword list values: sanitized
    - structs, implementing Jason.Encoder: ignored
    - structs, without Jason.Encoder: sanitized
    """ do
      metadata = [
        long_string: String.duplicate("Very long string", 20),
        keyword_list: [password: "secret"],
        struct_with_jason_encoder_impl: %JasonEncodableStruct{name: "A", password: "secret"},
        struct_with_no_jason_encoder_impl: %SimpleStruct{
          name: "A",
          password: "secret",
          not_loaded_assoc: %{__struct__: Ecto.Association.NotLoaded}
        }
      ]

      assert %{
               long_string: shortened_string,
               keyword_list: %{password: "[FILTERED]"},
               struct_with_jason_encoder_impl: %JasonEncodableStruct{
                 name: "A",
                 password: "secret"
               },
               struct_with_no_jason_encoder_impl: %{
                 name: "A",
                 password: "[FILTERED]",
                 not_loaded_assoc: :not_loaded
               }
             } = Loggable.sanitize(metadata, sensitive_keys: [:password], max_string_size: 50)

      assert String.length(shortened_string) == 53
    end
  end

  describe "prevents Jason encoding errors" do
    test "allows atoms, nils, numbers, booleans, printable binaries" do
      assert :hello == Loggable.sanitize(:hello)
      assert nil == Loggable.sanitize(nil)
      assert 1 == Loggable.sanitize(1)
      assert true == Loggable.sanitize(true)
      assert false == Loggable.sanitize(false)
      assert "hello" == Loggable.sanitize("hello")
    end

    test "inspects non-printable binaries" do
      assert "<<104, 101, 108, 108, 111, 0>>" == Loggable.sanitize("hello" <> <<0>>)
    end

    test "converts tuples to lists" do
      assert [1, 2, 3] == Loggable.sanitize({1, 2, 3})
    end

    test "converts nested tuples to nested lists" do
      assert [[2000, 1, 1], [13, 30, 15]] == Loggable.sanitize({{2000, 1, 1}, {13, 30, 15}})
    end

    test "converts Keyword lists to maps" do
      assert %{a: 1, b: 2} == Loggable.sanitize(a: 1, b: 2)
    end

    test "converts non-string map keys" do
      assert Loggable.sanitize(%{1 => 2}) == %{1 => 2}
      assert Loggable.sanitize(%{:a => 1}) == %{:a => 1}
      assert Loggable.sanitize(%{{"a", "b"} => 1}) == %{"{\"a\", \"b\"}" => 1}
      assert Loggable.sanitize(%{%{a: 1, b: 2} => 3}) == %{"%{a: 1, b: 2}" => 3}
      assert Loggable.sanitize(%{[{:a, :b}] => 3}) == %{"[a: :b]" => 3}
    end

    test "inspects functions" do
      assert "&StathamLogger.Loggable.sanitize/2" ==
               Loggable.sanitize(&Loggable.sanitize/2)
    end

    test "inspects pids" do
      assert inspect(self()) == Loggable.sanitize(self())
    end

    test "doesn't choke on things that look like keyword lists but aren't" do
      assert [[:a, 1], [:b, 2, :c]] == Loggable.sanitize([{:a, 1}, {:b, 2, :c}])
    end

    test "formats nested structures" do
      input = %{
        foo: [
          foo_a: %{"x" => 1, "y" => %{id: 1}},
          foo_b: [foo_b_1: 1, foo_b_2: ["2a", "2b"]]
        ],
        self: self()
      }

      assert %{
               foo: %{
                 foo_a: %{"x" => 1, "y" => %{id: 1}},
                 foo_b: %{foo_b_1: 1, foo_b_2: ["2a", "2b"]}
               },
               self: inspect(self())
             } == Loggable.sanitize(input)
    end
  end
end
