module Lox
  abstract class LoxObject
    abstract def print_representation : String
  end

  # We could probably just use Crystal's String type here instead. But this was
  # a good first exercise in implementing LoxObjects.
  class StringObject < LoxObject
    @@interned = Set(StringObject).new

    @chars : Array(Char)
    @hash : UInt64

    getter :chars, :hash

    def print_representation : String
      chars.join
    end

    def StringObject.new(chars : Array(Char))
      hash = chars.hash

      # If we've already interned this string, return the existing StringObject
      # instance.
      @@interned.each do |objstr|
        return objstr if objstr.chars.size == chars.size &&
          objstr.hash == hash &&
          objstr.chars == chars
      end

      # Otherwise, instantiate a new StringObject instance, intern and return
      # it.
      instance = StringObject.allocate
      instance.initialize(chars, hash)
      @@interned << instance
      instance
    end

    def initialize(@chars, @hash)
    end
  end

  class FunctionObject < LoxObject
    @name : StringObject
    @arity : Int32
    @chunk : Chunk

    property :arity
    getter :name, :chunk

    def print_representation : String
      return "<script>" if @name.chars.empty?

      "<fn #{@name.print_representation}>"
    end

    def initialize(@name, @arity, @chunk)
    end
  end

  alias NativeFunction = Proc(Array(Value), Value)

  class NativeFunctionObject < LoxObject
    @native_function : NativeFunction

    getter :name, :native_function

    def print_representation : String
      "<native fn>"
    end

    def initialize(@native_function)
    end
  end
end

