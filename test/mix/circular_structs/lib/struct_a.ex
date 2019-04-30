defmodule StructA do
  # use Ecto.Schema
  # schema "a_schema" do
  #   field :somefield, :string
  #   has_one :child_ref, StructB
  # end

  defstruct [a: nil, b: 4]
  @really :"StructB"
end
