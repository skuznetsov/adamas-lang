require "./compiler/cli"
require "./compiler/formatter"
require "./compiler/frontend/lexer"
require "./compiler/frontend/parser"

module Adamas
  module Compiler
    Lexer = Frontend::Lexer
    Parser = Frontend::Parser
  end
end
