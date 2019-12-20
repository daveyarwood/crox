module Lox
  class Scanner
    def initialize(@input : String)
      @start = 0
      @current = 0
      @line = 1
    end

    def eof? : Bool
      @current >= @input.size
    end

    def peek : Char | Nil
      @input[@current] unless eof?
    end

    def peek_next : Char | Nil
      @input[@current + 1] unless @current + 1 >= @input.size
    end

    def advance! : Char
      @current += 1
      @input[@current - 1]
    end

    def match!(expected : Char) : Bool
      if peek == expected
        @current += 1
        true
      else
        false
      end
    end

    def token(type : TokenType) : Token
      Token.new type, @input[@start...@current], @start, @line
    end

    def error_token(msg : String) : Token
      Token.new TokenType::Error, msg, @start, @line
    end

    def skip_whitespace!
      while true
        case peek
        when ' ', '\r', '\t'
          advance!
        when '\n'
          @line += 1
          advance!
        when '/'
          break unless peek_next == '/'
          # A comment goes until the end of the line (or EOF).
          while peek != '\n' && !eof?;
            advance!
          end
        else
          break
        end
      end
    end

    def string_token! : Token
      while peek != '"' && !eof?
        @line += 1 if peek == '\n'
        advance!
      end

      return error_token("Unterminated string.") if eof?

      # consume the closing "
      advance!
      token TokenType::String
    end

    def number_token! : Token
      while peek.try &.ascii_number?(10); advance!; end

      if peek == '.' && peek_next.try &.ascii_number?(10)
        # consume the .
        advance!
        while peek.try &.ascii_number?(10); advance!; end
      end

      token TokenType::Number
    end

    # This is probably not as fast as the algorithm in the book, but I'm gonna
    # do it anyway because I'm curious how much it really matters.
    def identifier_type : TokenType
      case @input[@start...@current]
      when "and"
        TokenType::And
      when "class"
        TokenType::Class
      when "else"
        TokenType::Else
      when "false"
        TokenType::False
      when "for"
        TokenType::For
      when "fun"
        TokenType::Fun
      when "if"
        TokenType::If
      when "nil"
        TokenType::Nil
      when "or"
        TokenType::Or
      when "print"
        TokenType::Print
      when "return"
        TokenType::Return
      when "super"
        TokenType::Super
      when "this"
        TokenType::This
      when "true"
        TokenType::True
      when "var"
        TokenType::Var
      when "while"
        TokenType::While
      else
        TokenType::Identifier
      end
    end

    def identifier_token! : Token
      while peek.try &.in_set?("A-Za-z_") || peek.try &.ascii_number?(10)
        advance!
      end

      token identifier_type
    end

    def scan_token! : Token
      skip_whitespace!

      @start = @current
      return token(TokenType::EOF) if eof?

      case advance!
      when '('
        token TokenType::LeftParen
      when ')'
        token TokenType::RightParen
      when '{'
        token TokenType::LeftBrace
      when '}'
        token TokenType::RightBrace
      when ';'
        token TokenType::Semicolon
      when ','
        token TokenType::Comma
      when '.'
        token TokenType::Dot
      when '-'
        token TokenType::Minus
      when '+'
        token TokenType::Plus
      when '/'
        token TokenType::Slash
      when '*'
        token TokenType::Star
      when '!'
        token(match!('=') ? TokenType::BangEqual : TokenType::Bang)
      when '='
        token(match!('=') ? TokenType::EqualEqual : TokenType::Equal)
      when '<'
        token(match!('=') ? TokenType::LessEqual : TokenType::Less)
      when '>'
        token(match!('=') ? TokenType::GreaterEqual : TokenType::Greater)
      when '"'
        string_token!
      when .ascii_number?(10) # 0-9
        number_token!
      when .in_set?("A-Za-z_")
        identifier_token!
      else
        error_token("Unexpected character.")
      end
    end
  end
end
