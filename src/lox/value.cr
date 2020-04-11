module Lox
  alias Value = Nil | Bool | Float64 | Obj

  def self.print_representation(value : Value) : String
    if value.is_a? Obj
      value.print_representation
    else
      value.inspect
    end
  end
end

