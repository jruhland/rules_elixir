defmodule StructB do
  use Ecto.Schema
  schema "b_schema" do
    field :myfield, :string
    belongs_to :parent_ref, StructA
  end

  @reallyB StructA
end
             
  
