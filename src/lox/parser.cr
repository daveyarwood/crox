module Lox
  # Parsing and compiling are sort of the same thing, in a sense; the line
  # between them is blurry. For the purposes of what we're doing here, the
  # compiler is doing most of the work and this "Parser" is really just a
  # mutable struct that holds the state of compilation.
  struct Parser
    property previous, current, had_error, panic_mode

    def initialize(
      @previous : Token, @current : Token, @had_error : Bool, @panic_mode : Bool
    )
    end
  end

  enum Precedence
    None
    Assignment # =
    Or         # or
    And        # and
    Equality   # == !=
    Comparison # < > <= >=
    Term       # + -
    Factor     # * /
    Unary      # ! -
    Call       # . ()
    Primary
  end

  alias ParseFn = (->)

  # See `Compiler#parse_rule` for a table of TokenType => ParseRule.
  record ParseRule,
    prefix : ParseFn | Nil,
    infix : ParseFn | Nil,
    precedence : Precedence
end
