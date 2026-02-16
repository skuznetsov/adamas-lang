require "./src/compiler/frontend/lexer"
require "./src/compiler/frontend/parser"

module CrystalV2::Compiler::Frontend
  source = "pp M::A"
  lexer = Lexer.new(source)
  tokens = lexer.lex
  parser = Parser.new(tokens, source)
  program = parser.parse

  puts "AST for: #{source}"
  program.roots.each do |root_id|
    node = program.arena[root_id]
    puts "Root: #{node.class} span=#{node.span.start_column}-#{node.span.end_column}"

    if node.is_a?(CallNode)
      puts "  Callee: #{node.callee}"
      node.args.each_with_index do |arg_id, i|
        arg = program.arena[arg_id]
        puts "  Arg #{i}: #{arg.class} span=#{arg.span.start_column}-#{arg.span.end_column}"
        if arg.is_a?(PathNode)
          if left = arg.left
            left_node = program.arena[left]
            puts "    Left: #{left_node.class} span=#{left_node.span.start_column}-#{left_node.span.end_column}"
          end
          right_node = program.arena[arg.right]
          puts "    Right: #{right_node.class} span=#{right_node.span.start_column}-#{right_node.span.end_column}"
        end
      end
    end
  end
end
