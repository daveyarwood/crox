module Lox
  abstract class Obj
    abstract def print_representation : String
  end

  # We could probably just use Crystal's String type here instead. But soon,
  # we'll need to add other types of Objs, like instances and functions. So it's
  # good to go ahead and lay the groundwork now.
  class ObjString < Obj
    @@interned = Set(ObjString).new

    @chars : Array(Char)
    @hash : UInt64

    getter :chars, :hash

    def print_representation : String
      chars.join
    end

    def ObjString.new(chars : Array(Char))
      hash = chars.hash

      # If we've already interned this string, return the existing ObjString
      # instance.
      @@interned.each do |objstr|
        return objstr if objstr.chars.size == chars.size &&
          objstr.hash == hash &&
          objstr.chars == chars
      end

      # Otherwise, instantiate a new ObjString instance, intern and return it.
      instance = ObjString.allocate
      instance.initialize(chars, hash)
      @@interned << instance
      instance
    end

    def initialize(chars : Array(Char), hash : UInt64)
      @chars = chars
      @hash = hash
    end
  end
end

