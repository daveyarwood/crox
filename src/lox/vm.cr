module Lox
  module VM
    extend self

    # These are here so that the types can be Foo instead of (Foo | Nil).
    @@stack = [] of Lox::Value
    @@chunk = Chunk.new
    @@byte_index = 0

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

    # instruction pointer
    def ip : Byte
      @@chunk.bytes[@@byte_index]
    end

    def read_byte! : Byte
      # store the current byte so we can return it
      byte = ip
      # increment the instruction pointer so it points to the NEXT byte
      @@byte_index += 1
      # return the byte we just read
      byte
    end

    def read_constant! : Lox::Value
      @@chunk.constants[read_byte!]
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

    def interpret!(chunk : Chunk) : InterpretResult
      @@chunk = chunk
      @@byte_index = 0
      run!
    end

    def interpret!(input : String) : InterpretResult
      chunk = Lox::Compiler.compile(input)
      return InterpretResult::CompileError if chunk.nil?
      @@chunk = chunk
      @@byte_index = 0
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
      when InterpretResult::CompileError
        exit 65
      when InterpretResult::RuntimeError
        exit 70
      end
    end

    def runtime_error!(format : String, *args : Object)
      STDERR.printf format + "\n", *args
      line_number = @@chunk.line_numbers[@@byte_index]
      STDERR.printf "[line %d] in script\n", line_number
      reset_stack!
    end

    # The behavior of splat arguments in Crystal is a little unexpected. Given
    # the definition above where the overload is (String, *Object), I would
    # expect that passing in just a string and no additional would work, but
    # instead, I get this error:
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
      while true
        instruction = Opcode.new(read_byte!)

        {% if flag?(:debug_trace_execution) %}
          puts "stack: #{@@stack}, instruction: #{instruction}"
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
          b = pop!
          a = pop!
          push! a == b
        when Opcode::Greater
          binary_op!(:>) || return InterpretResult::RuntimeError
        when Opcode::Less
          binary_op!(:<) || return InterpretResult::RuntimeError
        when Opcode::Add
          binary_op!(:+) || return InterpretResult::RuntimeError
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
          puts "return: #{pop!}"
          return InterpretResult::OK
        end
      end
    end
  end
end
