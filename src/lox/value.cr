module Lox
  alias Value = Nil | Bool | Float64 | LoxObject

  def self.print_representation(value : Value) : String
    if value.is_a? LoxObject
      value.print_representation
    else
      value.inspect
    end
  end
end

