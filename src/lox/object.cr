module Lox
  abstract class Obj
  end

  # We could probably just use Crystal's String type here instead. But soon,
  # we'll need to add other types of Objs, like instances and functions. So it's
  # good to go ahead and lay the groundwork now.
  class ObjString < Obj
    getter :chars

    def initialize(chars : Array(Char))
      @chars = chars
    end
  end
end

