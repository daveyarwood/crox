require "./lox/*"

chunk = Lox::Chunk.new
chunk.write 1, Lox::Opcode::Return
chunk.write 2, Lox::Opcode::Constant
chunk.write 2, chunk.add_constant(42.0)
p chunk.disassemble
