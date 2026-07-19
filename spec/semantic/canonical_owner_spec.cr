require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/semantic/compile_shadow_aggregate"
require "../semantic_cli_helpers"

include SemanticCliSpecHelpers

class Adamas::HIR::AstToHir
  def __test_arena_for_expr(expr_id : Adamas::Compiler::Frontend::ExprId) : Adamas::Compiler::Frontend::ArenaLike?
    arena_for_expr?(expr_id)
  end
end

private def parse_into_shared_owner(
  source : String,
  arena : Adamas::Compiler::Frontend::AstArena,
) : {Array(Adamas::Compiler::Frontend::ExprId), Adamas::Compiler::Frontend::Parser}
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer, arena)
  {parser.parse_program_roots, parser}
end

private def parse_arena_and_roots_without_pool(
  source : String,
) : {Adamas::Compiler::Frontend::AstArena, Array(Adamas::Compiler::Frontend::ExprId)}
  arena = Adamas::Compiler::Frontend::AstArena.new
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer, arena)
  roots = parser.parse_program_roots
  {arena, roots}
end

private def parse_into_existing_arena_without_pool(
  source : String,
  arena : Adamas::Compiler::Frontend::AstArena,
) : Array(Adamas::Compiler::Frontend::ExprId)
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer, arena)
  parser.parse_program_roots
end

private def generate_gc_churn : Nil
  garbage = [] of String
  512.times do |index|
    garbage << String.build do |io|
      io << "gc_churn_"
      io << index
    end
  end
end

describe "canonical semantic syntax owner" do
  it "does not equate independently parsed arenas with colliding local spans" do
    source = "value = 1\n"
    first = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source)
    )
    second = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source)
    )
    first_roots = first.parse_program_roots
    second_roots = second.parse_program_roots

    first_roots.first.index.should eq second_roots.first.index
    first.arena[first_roots.first].span.should eq second.arena[second_roots.first].span
    first.arena.object_id.should_not eq second.arena.object_id
    first.arena.debug_node_address(first_roots.first).should_not eq second.arena.debug_node_address(second_roots.first)
  end

  it "gives shared-owner units global ids and zero-copy node addresses" do
    shared = Adamas::Compiler::Frontend::AstArena.new
    first_roots, _first_parser = parse_into_shared_owner("class First\nend\n", shared)
    second_start = shared.size
    second_roots, _second_parser = parse_into_shared_owner("class Second\n  VALUE = 1\nend\n", shared)
    second_end = shared.size

    first_view = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
      shared,
      0,
      second_start,
      "class First\nend\n",
      second_end,
    )
    second_view = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
      shared,
      second_start,
      second_end,
      "class Second\n  VALUE = 1\nend\n",
      second_end,
    )

    first_roots.first.index.should be < second_roots.first.index
    first_view.extra_sources.should eq ["class First\nend\n"]
    second_view.extra_sources.should eq ["class Second\n  VALUE = 1\nend\n"]
    first_view[first_roots.first].should be_a(Adamas::Compiler::Frontend::ClassNode)
    second_view.debug_node_address(second_roots.first).should eq shared.debug_node_address(second_roots.first)

    embedded = Adamas::Compiler::Frontend::NodeDispatch.get_child_exprs(shared, second_roots.first).first
    first_view[embedded].should eq shared[embedded]
    second_view[embedded].should eq shared[embedded]
    second_view.debug_node_address(embedded).should eq shared.debug_node_address(embedded)

    generated_first = first_view.add(shared[first_roots.first])
    generated_second = second_view.add(shared[second_roots.first])
    generated_first.index.should be >= second_end
    generated_second.index.should be >= second_end
    generated_first.index.should_not eq generated_second.index
    second_view.source_owner_for(second_roots.first).should eq shared
    first_view.source_owner_for(first_roots.first).should eq shared
    second_view.source_owner_for(generated_second).should be_nil
    first_view.source_owner_for(generated_first).should be_nil
    first_view.owns_generated_id?(generated_first).should be_true
    first_view.owns_generated_id?(generated_second).should be_false
    second_view.owns_generated_id?(generated_second).should be_true
    second_view.owns_generated_id?(generated_first).should be_false
    first_view[generated_first].should eq shared[first_roots.first]
    second_view[generated_second].should eq shared[second_roots.first]
    first_view[generated_second]?.should be_nil
    second_view[generated_first]?.should be_nil
    first_view.typed?(generated_second).should be_false
    second_view.typed?(generated_first).should be_false
    first_view.debug_node_address(generated_second).should eq 0_u64
    second_view.debug_node_address(generated_first).should eq 0_u64
    expect_raises(IndexError) { first_view[generated_second] }
    expect_raises(IndexError) { second_view[generated_first] }
    first_view.debug_node_address(generated_first).should eq shared.debug_node_address(generated_first)
    second_view.debug_node_address(generated_second).should eq shared.debug_node_address(generated_second)

    unregistered = shared.add(shared[second_roots.first])
    first_view.source_owner_for(unregistered).should be_nil
    first_view.owns_generated_id?(unregistered).should be_false
    first_view[unregistered]?.should be_nil
    first_view.typed?(unregistered).should be_false
    first_view.debug_node_address(unregistered).should eq 0_u64
    expect_raises(IndexError) { first_view[unregistered] }
  end

  it "builds a canonical aggregate from original nodes and diagnostics without parsing" do
    shared = Adamas::Compiler::Frontend::AstArena.new
    roots, parser = parse_into_shared_owner("value = 1\n)\n", shared)
    input = Adamas::Compiler::Semantic::CompileShadowAggregate::CanonicalUnitInput.new(
      path: "broken.cr",
      source: "value = 1\n)\n",
      roots: roots,
      parse_diagnostics: parser.diagnostics,
      string_pool: parser.string_pool,
    )

    aggregate = Adamas::Compiler::Semantic::CompileShadowAggregate.build_canonical(shared, [input])
    aggregate.program.arena.should eq shared
    aggregate.program.roots.should eq roots
    aggregate.unit_index_for(roots.first).should eq 0
    aggregate.parse_diagnostics.size.should eq parser.diagnostics.size
    aggregate.source_for_path("broken.cr").should eq "value = 1\n)\n"
    aggregate.string_pool_count.should eq 1
    aggregate.retains_string_pool?(parser.string_pool).should be_true
  end

  it "retains parser string pools on the arena across GC churn" do
    shared, _roots = parse_arena_and_roots_without_pool("stable_name = 1\nother_name\n")
    shared.string_pool_count.should eq 1

    generate_gc_churn
    GC.collect

    names = shared.nodes.compact_map do |node|
      if identifier = node.as?(Adamas::Compiler::Frontend::IdentifierNode)
        String.new(identifier.name)
      end
    end
    names.should contain "stable_name"
    names.should contain "other_name"
  end

  it "retains generated parser pools on canonical views" do
    shared = Adamas::Compiler::Frontend::AstArena.new
    parsed_roots, _parser = parse_into_shared_owner("class Parsed\nend\n", shared)
    parsed_limit = shared.size
    view = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
      shared,
      0,
      parsed_limit,
      "class Parsed\nend\n",
      parsed_limit,
    )

    generated_roots = parse_into_existing_arena_without_pool("generated_name\n", view)
    generated = generated_roots.first
    view.string_pool_count.should eq 1
    shared.string_pool_count.should eq 1
    view.owns_generated_id?(generated).should be_true

    generate_gc_churn
    GC.collect

    identifier = view[generated].as(Adamas::Compiler::Frontend::IdentifierNode)
    String.new(identifier.name).should eq "generated_name"
  end

  it "routes a parsed id to its owning view instead of the current view" do
    shared = Adamas::Compiler::Frontend::AstArena.new
    first_roots, _first_parser = parse_into_shared_owner("class First\nend\n", shared)
    second_start = shared.size
    second_roots, _second_parser = parse_into_shared_owner("class Second\nend\n", shared)
    parsed_limit = shared.size

    first_view = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
      shared,
      0,
      second_start,
      "class First\nend\n",
      parsed_limit,
    )
    second_view = Adamas::Compiler::Frontend::CanonicalSyntaxView.new(
      shared,
      second_start,
      parsed_limit,
      "class Second\nend\n",
      parsed_limit,
    )
    generated_first = first_view.add(shared[first_roots.first])
    generated_second = second_view.add(shared[second_roots.first])
    unregistered = shared.add(shared[second_roots.first])

    converter = Adamas::HIR::AstToHir.new(first_view, "canonical-owner-test")
    converter.bootstrap_bind_main_arenas([first_view, second_view])
    converter.__test_arena_for_expr(first_roots.first).should eq first_view
    converter.__test_arena_for_expr(second_roots.first).should eq second_view
    converter.__test_arena_for_expr(generated_first).should eq first_view
    converter.__test_arena_for_expr(generated_second).should eq second_view
    converter.__test_arena_for_expr(unregistered).should be_nil
  end

  it "uses the canonical factory for the cross-file semantic compile route" do
    with_temp_shadow_project({
      "dep.cr" => "VALUE = 1\n",
      "main.cr" => "require \"./dep\"\nVALUE\n",
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        status = Adamas::Compiler::CLI.new([
          main_path,
          "--no-prelude",
          "--stats",
          "--verbose",
          "--no-link",
          "-o",
          output_path,
        ]).run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("syntax_owner=canonical")
      out_io.to_s.should contain("files=2")
      err_io.to_s.should be_empty
    end
  end

  it "keeps the legacy shadow builder out of the production prepass" do
    source = File.read(File.join(__DIR__, "../../src/compiler/cli.cr"))
    prepass_start = source.index("private def run_semantic_compile_prepass").not_nil!
    prepass_tail = source.byte_slice(prepass_start, source.bytesize - prepass_start).not_nil!
    prepass_end = prepass_tail.index("\n      private def ").not_nil!
    prepass = prepass_tail.byte_slice(0, prepass_end).not_nil!
    prepass.should_not contain("build_semantic_shadow_aggregate")

    parse_pos = source.index("parse_file_recursive(prelude_path").not_nil!
    semantic_gate_pos = source.index("semantic_compile_active = semantic_compile_enabled?").not_nil!
    semantic_gate_pos.should be < parse_pos
  end
end
