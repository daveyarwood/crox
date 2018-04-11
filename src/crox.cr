require "./lox/*"

Lox::VM.start!

chunk = Lox::Chunk.new

chunk.write 1, Lox::Opcode::Constant
chunk.write 1, chunk.add_constant(1.2)
chunk.write 1, Lox::Opcode::Constant
chunk.write 1, chunk.add_constant(3.4)
chunk.write 1, Lox::Opcode::Add

chunk.write 1, Lox::Opcode::Constant
chunk.write 1, chunk.add_constant(5.6)
chunk.write 1, Lox::Opcode::Divide

chunk.write 1, Lox::Opcode::Negate

chunk.write 1, Lox::Opcode::Return

p chunk.disassemble

Lox::VM.interpret!(chunk)
Lox::VM.stop!
