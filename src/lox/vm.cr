module Lox
  module VM
    extend self

    # These are here so that the types can be Foo instead of (Foo | Nil).
    @@stack = [] of Lox::Value
    @@chunk = Chunk.new
    @@byte_index = 0

    def push!(value)
      @@stack << value
    end

    def pop!
      @@stack.pop
    end

    def start!
      @@stack = [] of Lox::Value
    end

    def stop!
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
      b = pop!
      a = pop!
      push! (a {{op.id}} b)
    end

    def interpret!(chunk : Chunk) : InterpretResult
      @@chunk = chunk
      @@byte_index = 0
      run!
    end

    def interpret!(input : String) : InterpretResult
      Lox::Compiler.compile(input)
      InterpretResult::OK
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

    def run! : InterpretResult
      while true
        instruction = Opcode.new(read_byte!)

        {% if flag?(:debug_trace_execution) %}
          puts "stack: #{@@stack}"
          p instruction
        {% end %}

        case instruction
        when Opcode::Constant
          constant = read_constant!
          push! constant
        when Opcode::Add
          binary_op!(:+)
        when Opcode::Subtract
          binary_op!(:-)
        when Opcode::Multiply
          binary_op!(:*)
        when Opcode::Divide
          binary_op!(:/)
        when Opcode::Negate
          push!(pop! * -1)
        when Opcode::Return
          puts "return: #{pop!}"
          return InterpretResult::OK
        end
      end
    end
  end
end
