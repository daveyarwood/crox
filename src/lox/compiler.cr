module Lox
  module Compiler
    extend self

    class Local
      property name, depth

      @depth : Int32 | Nil

      def initialize(@name : Token)
        # Locals start in an "uninitialized" state; for `depth`, nil is a
        # sentinel value meaning "uninitialized". Depth gets set to a non-nil
        # value (the current scope) during the process of defining a local
        # variable. (See `add_local!` and `define_variable!`)
        @depth = nil
      end
    end

    struct Scope
      property locals, locals_count, depth

      def initialize
        @locals = uninitialized Local[Byte::MAX]
        @locals_count = 0
        @depth = 0
      end
    end

    @@scope = Scope.new

    # This is here so that the type of @@scanner can be Scanner instead of
    # (Scanner | Nil).
    @@scanner = Scanner.new("")

    def begin_scope!
      @@scope.depth += 1
    end

    def end_scope!
      @@scope.depth -= 1

      # Traverse the locals backwards (most recent first) and pop off all of
      # the ones that are within the scope that we just ended.
      while @@scope.locals_count > 0
        local = @@scope.locals[@@scope.locals_count-1]
        break if local.depth != nil && local.depth.not_nil! <= @@scope.depth

        @@scope.locals_count -= 1
        emit_byte! Opcode::Pop.value
      end
    end

    def resolve_local(scope : Scope, name : Token) : Byte | Nil
      (@@scope.locals_count-1).downto(0).each do |i|
        local = @@scope.locals[i]

        if local.name.lexeme == name.lexeme
          # This error happens in cases like `{ var a = a; }`
          if local.depth.nil?
            error! "Cannot read local variable in its own initializer."
          end

          return i.to_u8
        end
      end

      return nil
    end

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
      grouping = ->(p : Precedence){grouping!(p)}
      unary    = ->(p : Precedence){unary!(p)}
      binary   = ->(p : Precedence){binary!(p)}
      number   = ->(p : Precedence){number!(p)}
      literal  = ->(p : Precedence){literal!(p)}
      string   = ->(p : Precedence){string!(p)}
      variable = ->(p : Precedence){variable!(p)}
      and      = ->(p : Precedence){and!(p)}
      or       = ->(p : Precedence){or!(p)}

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
      rules[TokenType::And]          = {nil,      and,    Precedence::And}
      rules[TokenType::Or]           = {nil,      or,     Precedence::Or}
      rules[TokenType::Nil]          = {literal,  nil,    Precedence::None}
      rules[TokenType::False]        = {literal,  nil,    Precedence::None}
      rules[TokenType::True]         = {literal,  nil,    Precedence::None}
      rules[TokenType::String]       = {string,   nil,    Precedence::None}
      rules[TokenType::Identifier]   = {variable, nil,    Precedence::None}

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

    def synchronize!
      @@parser.panic_mode = false

      # Skip tokens until we reach something that looks like a statement
      # boundary.
      until current_token_is TokenType::EOF
        return if previous_token_is TokenType::Semicolon

        case @@parser.current.type
        when TokenType::Class, TokenType::Fun, TokenType::Var, TokenType::For,
          TokenType::If, TokenType::While, TokenType::Print, TokenType::Return
          return
        else
          # keep going
        end

        advance!
      end
    end

    def current_token_is(type : TokenType) : Bool
      @@parser.current.type == type
    end

    def previous_token_is(type : TokenType) : Bool
      @@parser.previous.type == type
    end

    def advance!
      @@parser.previous = @@parser.current

      while true
        @@parser.current = @@scanner.scan_token!
        break unless current_token_is TokenType::Error
        # The book has `errorAtCurrent(parser.current.start)`, but
        # `errorAtCurrent` expects a String message, not an Int. I think the
        # code in the book might be wrong. The context about where the error
        # starts is included in the token (`parser.current`), so the thing we
        # should be passing in here is a message. I'm not 100% sure of what the
        # message should be just yet.
        error_at_current!("???")
      end
    end

    def match!(type : TokenType) : Bool
      if current_token_is(type)
        advance!
        true
      else
        false
      end
    end

    def consume!(type : TokenType, message : String)
      if current_token_is type
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

    def emit_jump!(instruction : Opcode) : Int
      emit_byte! instruction.value
      # These two bytes serve as a placeholder operand for the jump offset. We
      # can't fill them in right now because we don't know how far to jump yet.
      #
      # Later, when we know the offset, we backpatch it in - see `patch_jump!`
      emit_bytes! 0xff_u8, 0xff_u8

      # Return the offset of the first placeholder byte.
      current_chunk.bytes.size - 2
    end

    def emit_loop!(loop_start : Int)
      emit_byte! Opcode::Loop.value

      # This offset is calculated from the instruction we're currently at to the
      # loop_start point. The + 2 is to take into account the size of the Loop
      # instruction's own operands, which we also need to jump over.
      offset = current_chunk.bytes.size - loop_start + 2
      error! "Loop body too large." if offset > UInt16::MAX

      emit_byte! ((offset >> 8) & 0xff).to_u8
      emit_byte! (offset & 0xff).to_u8
    end

    def patch_jump!(offset : Int)
      # -2 to adjust for the bytecode for the jump offset itself
      jump = current_chunk.bytes.size - offset - 2

      if jump > UInt16::MAX
        error! "Too much code to jump over."
      end

      current_chunk.bytes[offset] = ((jump >> 8) & 0xff).to_u8
      current_chunk.bytes[offset + 1] = (jump & 0xff).to_u8
    end

    def make_constant!(value : Lox::Value) : Byte
      constant_index = current_chunk.add_constant!(value)

      # The constant index needs to fit into a single byte, which means we can
      # store up to Byte::MAX constants.
      if current_chunk.constants.size > Byte::MAX
        error! "Too many constants in one chunk."
        return 0.to_u8
      end

      constant_index.to_u8
    end

    def emit_constant!(value : Lox::Value)
      emit_bytes! Opcode::Constant.value, make_constant!(value)
    end

    def number!(precedence : Precedence) : Nil
      emit_constant! @@parser.previous.lexeme.to_f
    end

    def string!(precedence : Precedence) : Nil
      emit_constant! ObjString.new(@@parser.previous.lexeme.chars[1..-2])
    end

    def named_variable!(name : Token, precedence : Precedence)
      arg = resolve_local @@scope, name

      if arg.nil?
        arg = identifier_constant! name
        get_op = Opcode::GetGlobal
        set_op = Opcode::SetGlobal
      else
        get_op = Opcode::GetLocal
        set_op = Opcode::SetLocal
      end

      if precedence <= Precedence::Assignment && match! TokenType::Equal
        expression!
        emit_bytes! set_op.value, arg
      else
        emit_bytes! get_op.value, arg
      end
    end

    def variable!(precedence : Precedence) : Nil
      named_variable! @@parser.previous, precedence
    end

    def grouping!(precedence : Precedence) : Nil
      expression!
      consume! TokenType::RightParen, "Expect ')' after expression."
    end

    def unary!(precedence : Precedence) : Nil
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

    def binary!(precedence : Precedence) : Nil
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

    def literal!(precedence : Precedence) : Nil
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
      prefix_rule.call(precedence)

      while precedence <= parse_rule(@@parser.current.type).precedence
        advance!
        parse_rule(@@parser.previous.type).infix.not_nil!.call(precedence)
      end

      # If we get here, the program is trying to do something weird like:
      #
      #    a * b = c + d
      #
      # i.e. the left hand side of the '=' isn't something that can be assigned
      # to.
      if precedence <= Precedence::Assignment && match! TokenType::Equal
        error! "Invalid assignment target."
      end
    end

    def identifier_constant!(name : Token) : Byte
      make_constant! ObjString.new(name.lexeme.chars)
    end

    # The instructions to work with local variables refer to them by slot index,
    # and that index is stored in a single-byte operand, which means our VM
    # only supports up to Byte::MAX local variables in scope at a time.
    def add_local!(name : Token)
      if @@scope.locals_count == Byte::MAX
        error! "Too many local variables in function."
        return
      end

      # depth is notionally @@scope.depth, but we set it to nil initially as a
      # way of saying that the local is "uninitialized"; then, we set it to the
      # actual depth later in `define_variable!`
      #
      # We do this in order to avoid the following edge case:
      #
      # {
      #   var a = "outer";
      #   {
      #     var a = a;
      #   }
      # }
      local = Local.new(name)

      @@scope.locals[@@scope.locals_count] = local
      @@scope.locals_count += 1
    end

    def declare_variable!
      # global variables are implicitly declared
      return if @@scope.depth == 0

      name = @@parser.previous

      (@@scope.locals_count-1).downto(0) do |i|
        local = @@scope.locals[i]

        break if local.depth != nil && local.depth.not_nil! < @@scope.depth

        if name.lexeme == local.name.lexeme
          error! "A variable with this name was already declared in this scope."
        end
      end

      add_local! name
    end

    def parse_variable!(error_msg : String) : Byte
      consume! TokenType::Identifier, error_msg
      declare_variable!

      # local scope (return a dummy global table index)
      return 0_u8 if @@scope.depth > 0

      # global scope (record a global in the table and return its index)
      identifier_constant! @@parser.previous
    end

    def define_variable!(index : Byte)
      # local scope: initialize the variable
      if @@scope.depth > 0
        @@scope.locals[@@scope.locals_count-1].depth = @@scope.depth
        return
      end

      # global scope: define a global
      emit_bytes! Opcode::DefineGlobal.value, index
    end

    def and!(precedence : Precedence) : Nil
      # At this point, the left-hand side of the && has already been compiled
      # and its value is on top of the stack.
      #
      # Here, we skip the right-hand side of the && if the value on top of the
      # stack is false. We skip over the Pop instruction because we want to
      # leave the value on the stack and let it be the result of the entire &&
      # expression.
      end_jump = emit_jump! Opcode::JumpIfFalse

      # Otherwise, we discard the value and move on to evaluate the right-hand
      # side.
      emit_byte! Opcode::Pop.value
      parse_precedence! Precedence::And
      patch_jump! end_jump
    end

    def or!(precedence : Precedence) : Nil
      else_jump = emit_jump! Opcode::JumpIfFalse
      end_jump = emit_jump! Opcode::Jump

      patch_jump! else_jump
      emit_byte! Opcode::Pop.value

      parse_precedence! Precedence::Or
      patch_jump! end_jump
    end

    def expression!
      parse_precedence! Precedence::Assignment
    end

    def block!
      while !current_token_is(TokenType::RightBrace) &&
            !current_token_is(TokenType::EOF)
        declaration!
      end

      consume! TokenType::RightBrace, "Expect '}' after block."
    end

    def variable_declaration!
      index = parse_variable! "Expect variable name."

      if match! TokenType::Equal
        # var foo = 42;
        expression!
      else
        # var foo;
        emit_byte! Opcode::Nil.value
      end

      consume! TokenType::Semicolon, "Expect ';' after variable declaration."

      define_variable! index
    end

    def print_statement!
      expression!
      consume! TokenType::Semicolon, "Expect ';' after value."
      emit_byte! Opcode::Print.value
    end

    def expression_statement!
      expression!
      consume! TokenType::Semicolon, "Expect ';' after expression."
      emit_byte! Opcode::Pop.value
    end

    def if_statement!
      consume! TokenType::LeftParen, "Expect '(' after 'if'."
      expression!
      consume! TokenType::RightParen, "Expect ')' after condition."

      # jumps past the "then" branch if the condition is false
      then_jump = emit_jump! Opcode::JumpIfFalse
      # pop the condition value off the stack
      emit_byte! Opcode::Pop.value
      # "then" branch
      statement!

      # jumps past the "else" branch (if the VM gets here, then the condition
      # above was true, so we need to skip the "else" branch)
      else_jump = emit_jump! Opcode::Jump

      patch_jump! then_jump
      # pop the condition value off the stack (if the VM gets here, it means it
      # jumped over the Pop instruction above, so we need to do the Pop here)
      emit_byte! Opcode::Pop.value

      # (optional) "else" branch
      if match! TokenType::Else
        statement!
      end

      patch_jump! else_jump
    end

    def while_statement!
      loop_start = current_chunk.bytes.size

      consume! TokenType::LeftParen, "Expect '(' after 'while'."
      expression!
      consume! TokenType::RightParen, "Expect ')' after condition."

      # Jump over the body statement if the condition is false.
      exit_jump = emit_jump! Opcode::JumpIfFalse
      # Pop the condition value off the stack.
      emit_byte! Opcode::Pop.value
      # body of the "while" loop
      statement!

      emit_loop! loop_start

      patch_jump! exit_jump
      # Pop the condition value off the stack.
      emit_byte! Opcode::Pop.value
    end

    def for_statement!
      begin_scope!

      consume! TokenType::LeftParen, "Expect '(' after 'for'."

      if match! TokenType::Semicolon
        # no initializer
      elsif match! TokenType::Var
        variable_declaration!
      else
        expression_statement!
      end

      loop_start = current_chunk.bytes.size

      exit_jump = nil
      unless match! TokenType::Semicolon
        expression!
        consume! TokenType::Semicolon, "Expect ';' after loop condition."

        # Jump out of the loop if the condition is false.
        exit_jump = emit_jump! Opcode::JumpIfFalse
        # Pop the condition value off the stack.
        emit_byte! Opcode::Pop.value
      end

      unless match! TokenType::RightParen
        body_jump = emit_jump! Opcode::Jump

        increment_start = current_chunk.bytes.size
        expression!
        emit_byte! Opcode::Pop.value
        consume! TokenType::RightParen, "Expect ')' after for clauses."

        emit_loop! loop_start
        loop_start = increment_start
        patch_jump! body_jump
      end

      statement!

      emit_loop! loop_start

      unless exit_jump.nil?
        patch_jump! exit_jump
        # Pop the condition value off the stack.
        emit_byte! Opcode::Pop.value
      end

      end_scope!
    end

    def statement!
      if match! TokenType::Print
        print_statement!
      elsif match! TokenType::For
        for_statement!
      elsif match! TokenType::If
        if_statement!
      elsif match! TokenType::While
        while_statement!
      elsif match! TokenType::LeftBrace
        begin_scope!
        block!
        end_scope!
      else
        expression_statement!
      end
    end

    def declaration!
      if match! TokenType::Var
        variable_declaration!
      else
        statement!
      end

      synchronize! if @@parser.panic_mode
    end

    # TODO: Maybe this should return an error of some kind instead of Nil if the
    # input fails to compile?
    def compile(input : String) : Chunk | Nil
      @@chunk = Chunk.new
      @@scanner = Scanner.new(input)

      advance!

      until match! TokenType::EOF
        declaration!
      end

      # I'm not totally sure if this is right, but it's necessary right now in
      # order to communicate to the VM that we're done so that the VM can return
      # InterpretResult::OK.
      emit_return!

      return nil if @@parser.had_error

      {% if flag?(:debug_print_code) %}
        pp current_chunk.disassemble
      {% end %}

      return @@chunk
    end
  end
end
