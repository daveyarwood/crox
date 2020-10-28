module Lox
  alias Byte = UInt8

  enum Opcode : Byte
    Constant
    Nil
    True
    False
    Equal
    Greater
    Less
    Add
    Subtract
    Multiply
    Divide
    Not
    Negate
    Call
    Return
    Print
    Pop
    DefineGlobal
    GetGlobal
    SetGlobal
    GetLocal
    SetLocal
    Jump
    JumpIfFalse
    Loop
  end

  record UnknownOpcode, code : Byte

  alias Operand = Byte

  # An instruction is an opcode and zero or more operands
  alias Instruction = Tuple(Opcode, Array(Operand))

  # We track line numbers in another array, separate from the instructions, but
  # parallel. The indexes line up, so that we can retrieve the line number for
  # an instruction when needed, e.g. when there is an error.
  alias LineNumber = Int32

  class Chunk
    getter :bytes, :constants, :line_numbers

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
      (@constants.size - 1).to_u8
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
        when Opcode::Constant, Opcode::DefineGlobal, Opcode::GetGlobal,
             Opcode::SetGlobal, Opcode::GetLocal, Opcode::SetLocal, Opcode::Call
          i += 1
          {line, {code, [@bytes[i]]}}
        when Opcode::Jump, Opcode::JumpIfFalse, Opcode::Loop
          i += 2
          # The two operand bytes are read as a short representing the offset to
          # jump.
          #
          # * Jump jumps forward by the offset (adds the offset to the IP).
          # * JumpIfFalse does the same thing, but only if the value on top of
          #   the stack is false.
          # * Loop jumps backwards by the offset (subtracts the offset from the
          #   IP)
          #
          # offset = ((@bytes[i-1] << 8) | @bytes[i]).to_u16
          {line, {code, [@bytes[i-1], @bytes[i]]}}
        when Opcode::Nil, Opcode::False, Opcode::True, Opcode::Equal,
             Opcode::Greater, Opcode::Less, Opcode::Add, Opcode::Subtract,
             Opcode::Multiply, Opcode::Divide, Opcode::Not, Opcode::Negate,
             Opcode::Return, Opcode::Print, Opcode::Pop
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

