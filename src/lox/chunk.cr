module Lox
  enum Opcode : Int8
    Constant
    Add
    Subtract
    Multiply
    Divide
    Negate
    Return
  end

  record UnknownOpcode, code : Int8

  alias Byte = Int8
  alias Operand = Byte

  # An instruction is an opcode and zero or more operands
  alias Instruction = Tuple(Opcode, Array(Operand))

  # We track line numbers in another array, separate from the instructions, but
  # parallel. The indexes line up, so that we can retrieve the line number for
  # an instruction when needed, e.g. when there is an error.
  alias LineNumber = Int32

  class Chunk
    getter :bytes, :constants

    def initialize
      @bytes = [] of Byte
      @constants = [] of Lox::Value
      @line_numbers = [] of LineNumber
    end

    def write!(line : LineNumber, byte : Byte)
      @bytes << byte
      @line_numbers << line
    end

    def write!(line : LineNumber, opcode : Opcode)
      write! line, opcode.value
    end

    # Adds a constant to the constant pool and returns the index it got written
    # to, so the caller can retrieve it when needed.
    def add_constant!(constant : Lox::Value) : Byte
      @constants << constant
      (@constants.size - 1).to_i8
    end

    alias DisassemblerEntry = Tuple(LineNumber, Instruction | UnknownOpcode)

    # Returns a representation where the chunk's bytes are broken up into
    # instructions with their operands, correlated with line numbers.
    def disassemble : Array(DisassemblerEntry)
      result = [] of DisassemblerEntry
      i = 0
      while i < @bytes.size
        line = @line_numbers[i]
        code = Opcode.new(@bytes[i])
        result << case code
        when Opcode::Constant
          i += 1
          {line, {Opcode::Constant, [@bytes[i]]}}
        when Opcode::Add, Opcode::Subtract, Opcode::Multiply, Opcode::Divide,
             Opcode::Negate, Opcode::Return
          {line, {code, [] of Operand}}
        else
          {line, UnknownOpcode.new(code.value)}
        end
        i += 1
      end
      result
    end
  end
end

