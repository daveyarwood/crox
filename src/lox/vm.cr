module Lox
  module VM
    extend self

    def placeholder_fn : FunctionObject
      name = StringObject.new("".chars)
      FunctionObject.new(name, 0, Chunk.new)
    end

    class CallFrame
      property function, ip, slots

      @function : FunctionObject
      @ip : UInt8
      @slots : Array(Lox::Value)

      def initialize(@function, @ip, @slots)
      end
    end

    # We have to set a limit on call frames to avoid stack overflow, e.g. in the
    # case of infinite recursion.
    FRAMES_MAX = 64

    # These are here so that the types can be Foo instead of (Foo | Nil).
    #
    # NB: The book has us preallocating memory for the `frames` and `stacks` on
    # the heap and keeping track of how many we have. I'm doing something
    # simpler here because I don't care that much about performance, and maybe
    # Crystal does some optimizations under the hood anyway.
    @@frames = [] of CallFrame
    @@frame = CallFrame.new(placeholder_fn, 0.to_u8, [] of Lox::Value)
    @@stack = [] of Lox::Value
    @@globals = {} of StringObject => Lox::Value

    @@globals[StringObject.new("clock".chars)] = NativeFunctionObject.new(
      ->(args : Array(Lox::Value)) {
        Time.monotonic.seconds.to_f.as Lox::Value
      })

    def current_chunk
      @@frame.function.chunk
    end

    def reset_stack!
      @@stack = [] of Lox::Value
    end

    def push!(value)
      @@stack << value
    end

    def pop!
      @@stack.pop
    end

    def peek(distance)
      @@stack[-1 - distance]
    end

    enum InterpretResult
      OK
      CompileError
      RuntimeError
    end

    def current_byte : Byte
      current_chunk.bytes[@@frame.ip]
    end

    def read_short! : UInt16
      @@frame.ip += 2
      ((current_chunk.bytes[@@frame.ip-2] << 8) \
       | current_chunk.bytes[@@frame.ip-1]).to_u16
    end

    def read_byte! : Byte
      # store the current byte so we can return it
      byte = current_byte
      # increment the instruction pointer so it points to the NEXT byte
      @@frame.ip += 1
      # return the byte we just read
      byte
    end

    def read_constant! : Lox::Value
      current_chunk.constants[read_byte!]
    end

    macro binary_op!(op)
      if peek(0).is_a?(Float64) && peek(1).is_a?(Float64)
        %b = pop!.as(Float64)
        %a = pop!.as(Float64)
        push! (%a {{op.id}} %b)
        true
      else
        runtime_error! "Operands must be numbers."
        false
      end
    end

    def equal!
      b = pop!
      a = pop!

      case {a, b}
      when {StringObject, StringObject}
        push! a == b
      when {LoxObject, _}, {_, LoxObject}
        runtime_error! "Equality semantics undefined: #{a.class} == #{b.class}"
        return false
      else
        push! (a == b)
      end

      return true
    end

    def add!
      b = pop!
      a = pop!

      case {a, b}
      when {StringObject, StringObject}
        push! StringObject.new(a.chars + b.chars)
      when {Float64, Float64}
        push! (a + b)
      else
        runtime_error! "Operands must be two numbers or two strings."
        return false
      end

      return true
    end

    def interpret!(input : String) : InterpretResult
      function = Lox::Compiler.compile(input)
      return InterpretResult::CompileError if function.nil?

      push! function
      call_value! function, 0

      run!
    end

    def repl_session!
      while true
        print "> "
        input = gets
        break if input.nil?
        interpret!(input) unless input.blank?
      end
    end

    def run_file!(file : String)
      unless File.exists? file
        puts "Could not open file \"#{file}\"."
        exit 74
      end

      case interpret!(File.read(file))
      when InterpretResult::OK
        # no problem
      when InterpretResult::CompileError
        exit 65
      when InterpretResult::RuntimeError
        exit 70
      end
    end

    def runtime_error!(format : String, *args : Object)
      STDERR.printf format + "\n", *args

      @@frames.reverse.each do |frame|
        line_number = frame.function.chunk.line_numbers[frame.ip]
        if frame.function.name.chars.empty?
          location = "script"
        else
          location = "#{frame.function.name.chars.join}()"
        end
        STDERR.printf "[line %d] in %s\n", line_number, location
      end

      reset_stack!
    end

    # The behavior of splat arguments in Crystal is a little unexpected. Given
    # the definition above where the overload is (String, *Object), I would
    # expect that passing in just a string and no additional arguments would
    # work, but instead, I get this error:
    #
    # Error: no overload matches 'Lox::VM.runtime_error!' with type String
    #
    # Defining this overload for (String) works. I wasn't able to pass in an
    # empty tuple/array of object, e.g. *([] of Object) so I just pass in an
    # arbitrary tuple of one Nil, since the args shouldn't matter in this case.
    def runtime_error!(format : String)
      runtime_error! format, {nil}
    end

    def call!(function : FunctionObject, arg_count : Byte) : Bool
      unless arg_count == function.arity
        runtime_error! \
          "Expected %d arguments but got %d.", \
          function.arity, \
          arg_count

        return false
      end

      # Ensure that a deep call chain doesn't overflow the stack, e.g. in the
      # case of infinite recursion.
      if @@frames.size == FRAMES_MAX
        runtime_error! "Stack overflow."
        return false
      end

      # FIXME: That last argument is supposed to be translated from:
      #
      #   frame->slots = vm.stackTop - argCount - 1
      #
      # I'm supposed to be setting up the slots "pointer" (which is not a
      # pointer, in my implementation, but an actual array of slots) to give the
      # frame its window into the stack.
      #
      # Maybe the thing to do is to copy the current frame's slots from the IP
      # to the end? arg_count also needs to be considered though...
      #
      # --- if the code below works, remove the FIXME comment above ---
      #
      # In the C code, the slots are all stored in a single data structure, and
      # each call frame stores an instruction pointer (IP) to where it is in
      # that structure.
      #
      # In our version, we copy the slots we need into the new call frame. We
      # copy the topmost (argument count + 1) slots, the "+ 1" being there so
      # that we skip over local slot 0, which contains the function being
      # called. (The book says that we currently aren't using that slot, but we
      # will when we get to methods.)
      if @@frames.empty?
        slots = [] of Lox::Value
      elsif @@frames[-1].slots.empty?
        slots = [] of Lox::Value
      else
        slots = @@frames[-1].slots[(-1 - arg_count - 1)..-1]
      end
      @@frames << CallFrame.new(function, 0.to_u8, slots)
      return true
    end

    def call_value!(callee : Value, arg_count : Byte) : Bool
      case callee
      when FunctionObject
        return call! callee, arg_count
      when NativeFunctionObject
        if @@frames.empty?
          args = [] of Lox::Value
        elsif @@frames[-1].slots.empty?
          args = [] of Lox::Value
        else
          args = @@frames[-1].slots[(-1 - arg_count - 1)..-1]
        end

        # Pop the function object off of the stack.
        pop!

        # Push the result of calling the function onto the stack.
        push! callee.native_function.call(args)

        return true
      else
        runtime_error! "Can only call functions and classes."
        return false
      end
    end

    def run! : InterpretResult
      @@frame = @@frames[-1]

      while true
        instruction = Opcode.new(read_byte!)

        {% if flag?(:debug_trace_execution) %}
          puts "frames: #{@@frames.size}, stack: #{@@stack.map{|x| Lox.print_representation(x) }}, instruction: #{instruction}"
        {% end %}

        case instruction
        when Opcode::Constant
          constant = read_constant!
          push! constant
        when Opcode::Nil
          push! nil
        when Opcode::False
          push! false
        when Opcode::True
          push! true
        when Opcode::Equal
          equal! || return InterpretResult::RuntimeError
        when Opcode::Greater
          binary_op!(:>) || return InterpretResult::RuntimeError
        when Opcode::Less
          binary_op!(:<) || return InterpretResult::RuntimeError
        when Opcode::Add
          add! || return InterpretResult::RuntimeError
        when Opcode::Subtract
          binary_op!(:-) || return InterpretResult::RuntimeError
        when Opcode::Multiply
          binary_op!(:*) || return InterpretResult::RuntimeError
        when Opcode::Divide
          binary_op!(:/) || return InterpretResult::RuntimeError
        when Opcode::Not
          push! !pop!
        when Opcode::Negate
          if peek(0).is_a? Float64
            push!(pop!.as(Float64) * -1)
          else
            runtime_error! "Operand must be a number."
            return InterpretResult::RuntimeError
          end
        when Opcode::Call
          arg_count = read_byte!

          unless call_value! peek(arg_count), arg_count
            return InterpretResult::RuntimeError
          end

          # If call_value! is successful, there will be a new frame on the
          # CallFrame stack for the called function. We now set @@frame to the
          # new frame on top of the stack, so that when we go to read the next
          # instruction byte, it will be from the new frame. In other words, we
          # are jumping into the code for the function that has been called.
          @@frame = @@frames[-1]
        when Opcode::Return
          # Hang onto the return value so that we can push it onto the stack
          # at the end.
          result = pop!

          # Discard the returning function's CallFrame.
          @@frames.pop

          # If this is the very last CallFrame, that means we've finished
          # executing the top level code. The entire program is done, so we pop
          # the main script function from the stack and exit the interpreter.
          if @@frames.empty?
            pop!
            return InterpretResult::OK
          end

          # FIXME: Am I translating the C code correctly?
          push! result

          @@frame = @@frames[-1]
        when Opcode::Print
          puts Lox.print_representation(pop!)
        when Opcode::Pop
          pop!
        when Opcode::DefineGlobal
          name = read_constant!.as(StringObject)
          @@globals[name] = pop!
        when Opcode::GetGlobal
          name = read_constant!.as(StringObject)
          begin
            push! @@globals[name]
          rescue KeyError
            runtime_error! "Undefined variable '#{name.chars.join}'."
            return InterpretResult::RuntimeError
          end
        when Opcode::SetGlobal
          name = read_constant!.as(StringObject)
          unless @@globals.has_key? name
            runtime_error! "Undefined variable '#{name.chars.join}'"
            return InterpretResult::RuntimeError
          end
          # The books says that "assignment is an expression, so it needs to
          # leave the value [on the stack] in case the assignment is nested
          # inside some larger expression."
          @@globals[name] = peek(0)
        when Opcode::GetLocal
          # As an optimization, the stack serves a dual purpose as a place to
          # store locals. The indexes are kept in sync with
          # compiler.scope.locals, which is why we're dealing with stack indexes
          # directly here instead of just pushing and popping values via `push!`
          # and `pop!`.
          push! @@frame.slots[read_byte!]
        when Opcode::SetLocal
          # see comment above
          @@frame.slots[read_byte!] = peek(0)
        when Opcode::Jump
          offset = read_short!
          @@frame.ip += offset
        when Opcode::JumpIfFalse
          offset = read_short!
          @@frame.ip += offset unless peek(0)
        when Opcode::Loop
          offset = read_short!
          @@frame.ip -= offset
        end
      end
    end
  end
end
