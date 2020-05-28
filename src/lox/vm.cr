module Lox
  module VM
    extend self

    def placeholder_fn : FunctionObject
      name = StringObject.new("".chars)
      FunctionObject.new(name, 0, Chunk.new)
    end

    struct CallFrame
      property function, ip, slots

      @function : FunctionObject
      @ip : UInt8
      @slots : Array(Lox::Value)

      def initialize(@function, @ip, @slots)
      end
    end

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
      @@frames << CallFrame.new(function, @@frame.ip, @@stack)

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
      line_number = current_chunk.line_numbers[@@frame.ip]
      STDERR.printf "[line %d] in script\n", line_number
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

    def run! : InterpretResult
      @@frame = @@frames[-1]

      while true
        instruction = Opcode.new(read_byte!)

        {% if flag?(:debug_trace_execution) %}
          puts "stack: #{@@stack.map{|x| Lox.print_representation(x) }}, instruction: #{instruction}"
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
        when Opcode::Return
          return InterpretResult::OK
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
