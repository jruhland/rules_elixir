defmodule StructB do
  # use Ecto.Schema
  # schema "b_schema" do
  #   field :myfield, :string
  #   belongs_to :parent_ref, StructA
  # end

  defstruct [c: 4, d: 8888]
  @reallyB StructA
end
             
  
