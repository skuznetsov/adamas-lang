require "file_utils"
require "../src/compiler/lsp/ast_cache"
alias Frontend = Adamas::Compiler::Frontend
alias AstCache = Adamas::Compiler::LSP::AstCache
work = ARGV[0]
Dir.mkdir_p(work)
source_path = File.join(work, "source.cr")
File.write(source_path, "super(nil, cause: nil)\n")
arena = Frontend::AstArena.new
span = Frontend::Span.zero
value = arena.add(Frontend::NilNode.new(span))
name_span = Frontend::Span.new(10, 15, 2, 3, 2, 8)
value_span = Frontend::Span.new(17, 20, 2, 10, 2, 13)
named_arg = Frontend::NamedArgument.new("cause".to_slice, value, name_span, value_span)
root = arena.add(Frontend::SuperNode.new(span, [value], [named_arg]))
bare = arena.add(Frontend::SuperNode.new(span))
empty = arena.add(Frontend::SuperNode.new(span, [] of Frontend::ExprId, [] of Frontend::NamedArgument))
AstCache.new(arena, [root, bare, empty], Frontend::StringPool.new).save(source_path)
cache_path = AstCache.cache_path(source_path)
raw = File.read(cache_path).to_slice
old = raw.dup
old[5] = 0_u8
old[6] = 0_u8
old[7] = 0_u8
[(raw[4] - 1_u8)].each do |version|
  old[4] = version
  File.write(cache_path, old)
  abort "old cache format was admitted" unless AstCache.load(source_path).nil?
end
File.write(cache_path, raw)
loaded = AstCache.load(source_path) || abort "same-process cache load failed"
super_node = loaded.arena[loaded.roots.first].as(Frontend::SuperNode)
args = super_node.args || abort "super args disappeared"
abort "super arg count changed" unless args.size == 1
puts "PASS: old-version rejection"
named = super_node.named_args || abort "super named-argument labels disappeared after cache roundtrip"
abort "named-argument count changed" unless named.size == 1
abort "named-argument label changed" unless String.new(named[0].name) == "cause"
abort "named value lost its shared args identity" unless named[0].value == args[0]
puts "PASS: named super argument and shared value identity"
abort "named name span changed" unless named[0].name_span == name_span
abort "named value span changed" unless named[0].value_span == value_span
loaded_bare = loaded.arena[loaded.roots[1]].as(Frontend::SuperNode)
abort "bare super became explicit" unless loaded_bare.args.nil? && loaded_bare.named_args.nil?
loaded_empty = loaded.arena[loaded.roots[2]].as(Frontend::SuperNode)
abort "explicit empty super disappeared" unless loaded_empty.args.try(&.empty?) && loaded_empty.named_args.try(&.empty?)
puts "PASS: spans and absent versus empty arguments"
