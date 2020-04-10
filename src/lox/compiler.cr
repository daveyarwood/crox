module Lox
  module Compiler
    extend self

    # This is here so that the type of @@scanner can be Scanner instead of
    # (Scanner | Nil).
    @@scanner = Scanner.new("")

    # The initial state of `previous` and `current` doesn't really matter,
    # because they get filled in with actual tokens from the scanner when we do
    # the compilation.
    ARBITRARY = Token.new TokenType::Nil, "", 0, 0
    @@parser = Parser.new ARBITRARY, ARBITRARY, false, false

    @@chunk = Chunk.new

    # At the moment, we're only dealing with a single chunk, which we're storing
    # in a global variable. The logic will get more complicated later on when we
    # need to compile user-defined functions, so the logic of which chunk we're
    # compiling to is encapsulated in this function.
    def current_chunk
      @@chunk
    end

    def parse_rule(operator_type : TokenType) : ParseRule
      grouping = ->(){grouping!}
      unary    = ->(){unary!}
      binary   = ->(){binary!}
      number   = ->(){number!}
      literal  = ->(){literal!}
      string   = ->(){string!}

      rules =
        Hash(TokenType, Tuple(ParseFn|Nil, ParseFn|Nil, Precedence)).new(
        {nil, nil, Precedence::None}
      )

      rules[TokenType::LeftParen]    = {grouping, nil,    Precedence::None}
      rules[TokenType::Minus]        = {unary,    binary, Precedence::Term}
      rules[TokenType::Plus]         = {nil,      binary, Precedence::Term}
      rules[TokenType::Slash]        = {nil,      binary, Precedence::Factor}
      rules[TokenType::Star]         = {nil,      binary, Precedence::Factor}
      rules[TokenType::Bang]         = {unary,    nil,    Precedence::None}
      rules[TokenType::BangEqual]    = {nil,      binary, Precedence::Equality}
      rules[TokenType::EqualEqual]   = {nil,      binary, Precedence::Equality}
      rules[TokenType::Greater]      = {nil,     binary, Precedence::Comparison}
      rules[TokenType::GreaterEqual] = {nil,     binary, Precedence::Comparison}
      rules[TokenType::Less]         = {nil,     binary, Precedence::Comparison}
      rules[TokenType::LessEqual]    = {nil,     binary, Precedence::Comparison}
      rules[TokenType::Number]       = {number,   nil,    Precedence::None}
      rules[TokenType::Nil]          = {literal,  nil,    Precedence::None}
      rules[TokenType::False]        = {literal,  nil,    Precedence::None}
      rules[TokenType::True]         = {literal,  nil,    Precedence::None}
      rules[TokenType::String]       = {string,   nil,    Precedence::None}

      prefix, infix, precedence = rules[operator_type]

      ParseRule.new(prefix, infix, precedence)
    end

    def error_at!(token : Token, message : String)
      # When we're in panic mode, we want to suppress any additional errors from
      # being printed in order to keep the output from getting noisy. So we
      # continue to compile, but calls to `error_at!` return immediately without
      # printing any additional errors.
      return if @@parser.panic_mode
      @@parser.panic_mode = true

      msg = "[line #{token.line}] Error"

      case token.type
      when TokenType::EOF
        msg += " at end"
      when TokenType::Error
        # nothing to add
      else
        msg += sprintf(" at '%s'", token.lexeme)
      end

      msg += ": " + message

      STDERR.puts msg

      @@parser.had_error = true
    end

    def error!(message : String)
      error_at!(@@parser.previous, message)
    end

    def error_at_current!(message : String)
      error_at!(@@parser.current, message)
    end

    def advance!
      @@parser.previous = @@parser.current

      while true
        @@parser.current = @@scanner.scan_token!
        break unless @@parser.current.type == TokenType::Error
        # The book has `errorAtCurrent(parser.current.start)`, but
        # `errorAtCurrent` expects a String message, not an Int. I think the
        # code in the book might be wrong. The context about where the error
        # starts is included in the token (`parser.current`), so the thing we
        # should be passing in here is a message. I'm not 100% sure of what the
        # message should be just yet.
        error_at_current!("???")
      end
    end

    def consume!(type : TokenType, message : String)
      if @@parser.current.type == type
        advance!
      else
        error_at_current!(message)
      end
    end

    def emit_byte!(byte : Byte)
      current_chunk.write!(@@parser.previous.line, byte)
    end

    def emit_bytes!(*bytes : Byte)
      bytes.each {|byte| emit_byte!(byte)}
    end

    def emit_return!
      emit_byte! Opcode::Return.value
    end

    def make_constant!(value : Lox::Value) : Byte
      constant_index = current_chunk.add_constant!(value)

      # The constant index needs to fit into a single byte, which means we can
      # store up to Byte::MAX constants.
      if current_chunk.constants.size > Byte::MAX
        error! "Too many constants in one chunk."
        return 0.to_i8
      end

      constant_index.to_i8
    end

    def emit_constant!(value : Lox::Value)
      emit_bytes! Opcode::Constant.value, make_constant!(value)
    end

    def number! : Nil
      emit_constant! @@parser.previous.lexeme.to_f
    end

    def string! : Nil
      emit_constant! ObjString.new(@@parser.previous.lexeme.chars[1..-2])
    end

    def grouping! : Nil
      expression!
      consume!(TokenType::RightParen, "Expect ')' after expression.")
    end

    def unary! : Nil
      operator_type = @@parser.previous.type

      # Compile the operand.
      parse_precedence! Precedence::Unary

      # Emit the operator instruction.
      case operator_type
      when TokenType::Bang
        emit_byte! Opcode::Not.value
      when TokenType::Minus
        emit_byte! Opcode::Negate.value
      else
        error! "Unrecognized unary operator type"
      end
    end

    def binary! : Nil
      # Remember the operator.
      operator_type = @@parser.previous.type

      # Compile the right hand side operand.
      parse_precedence!(parse_rule(operator_type).precedence + 1)

      # Emit the operator instructions.
      case operator_type
      when TokenType::BangEqual
        emit_bytes! Opcode::Equal.value, Opcode::Not.value
      when TokenType::EqualEqual
        emit_byte! Opcode::Equal.value
      when TokenType::Greater
        emit_byte! Opcode::Greater.value
      when TokenType::GreaterEqual
        emit_bytes! Opcode::Less.value, Opcode::Not.value
      when TokenType::Less
        emit_byte! Opcode::Less.value
      when TokenType::LessEqual
        emit_bytes! Opcode::Greater.value, Opcode::Not.value
      when TokenType::Plus
        emit_byte! Opcode::Add.value
      when TokenType::Minus
        emit_byte! Opcode::Subtract.value
      when TokenType::Star
        emit_byte! Opcode::Multiply.value
      when TokenType::Slash
        emit_byte! Opcode::Divide.value
      else
        error! "Unrecognized binary operator type"
      end
    end

    def literal! : Nil
      case @@parser.previous.type
      when TokenType::Nil
        emit_byte! Opcode::Nil.value
      when TokenType::False
        emit_byte! Opcode::False.value
      when TokenType::True
        emit_byte! Opcode::True.value
      else
        error! "Unrecognized literal type"
      end
    end

    def parse_precedence!(precedence : Precedence)
      advance!

      prefix_rule = parse_rule(@@parser.previous.type).prefix
      if prefix_rule.nil?
        error! "Expect expression."
        return
      end
      prefix_rule.call()

      while precedence <= parse_rule(@@parser.current.type).precedence
        advance!
        parse_rule(@@parser.previous.type).infix.not_nil!.call()
      end
    end

    def expression!
      parse_precedence! Precedence::Assignment
    end

    # TODO: Maybe this should return an error of some kind instead of Nil if the
    # input fails to compile?
    def compile(input : String) : Chunk | Nil
      @@chunk = Chunk.new
      @@scanner = Scanner.new(input)
      advance!
      expression!
      consume!(TokenType::EOF, "Expected end of expression.")
      # Our initial goal is to compile expressions, so doing this temporarily in
      # order to shim the expression into a statement.
      emit_return!

      return nil if @@parser.had_error

      {% if flag?(:debug_print_code) %}
        pp current_chunk.disassemble
      {% end %}

      return @@chunk
    end
  end
end
