module Lox
  module Compiler
    extend self

    def compile(input : String)
      line = -1

      scanner = Scanner.new(input)
      while true
        token = scanner.scan_token
        if token.line == line
          print "    | "
        else
          printf "%4d ", token.line
        end
        printf "%s '%s'\n", token.type, token.lexeme
        break if token.type == TokenType::EOF
      end
    end
  end
end
