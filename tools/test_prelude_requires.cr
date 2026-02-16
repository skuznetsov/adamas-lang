require "../src/compiler/frontend/ast"
require "../src/compiler/frontend/parser"
require "../src/compiler/frontend/lexer"

alias Frontend = CrystalV2::Compiler::Frontend

PRELUDE_PATH = "/opt/homebrew/Cellar/crystal/1.18.2/share/crystal/src/prelude.cr"

def main
  source = File.read(PRELUDE_PATH)
  lexer = Frontend::Lexer.new(source)
  parser = Frontend::Parser.new(lexer, recovery_mode: true)
  program = parser.parse

  puts "Roots count: #{program.roots.size}"
  
  require_count = 0
  time_found = false
  
  program.roots.each do |root_id|
    node = program.arena[root_id]
    if node.is_a?(Frontend::RequireNode)
      require_count += 1
      path_expr = program.arena[node.path]
      if path_expr.is_a?(Frontend::StringNode)
        path_str = String.new(path_expr.value)
        puts "  require \"#{path_str}\""
        if path_str == "time"
          time_found = true
          puts "  ^^^ Found time!"
        end
      end
    end
  end
  
  puts "Total RequireNodes in roots: #{require_count}"
  puts "time found: #{time_found}"
end

main
