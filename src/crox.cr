require "./lox/*"

Lox::VM.start!

case ARGV.size
when 0
  Lox::VM.repl_session!
when 1
  Lox::VM.run_file! ARGV[0]
else
  puts "Usage: crox [path]"
  exit 64
end

Lox::VM.stop!
