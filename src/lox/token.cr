module Lox
  enum TokenType
    # Single-character tokens
    LeftParen
    RightParen
    LeftBrace
    RightBrace
    Comma
    Dot
    Minus
    Plus
    Semicolon
    Slash
    Star

    # One or two character tokens
    Bang
    BangEqual
    Equal
    EqualEqual
    Greater
    GreaterEqual
    Less
    LessEqual

    # Literals
    Identifier
    String
    Number

    # Keywords
    And
    Class
    Else
    False
    Fun
    For
    If
    Nil
    Or
    Print
    Return
    Super
    This
    True
    Var
    While

    # Other
    Error
    EOF
  end

  record Token, type : TokenType, lexeme : String, start : Int32, line : Int32
end
