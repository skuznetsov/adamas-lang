require "spec"
require "../../src/compiler/semantic/generated_overlay"

describe CrystalV2::Compiler::Semantic::GeneratedOverlay do
  it "builds an empty overlay through the explicit constructor" do
    overlay = CrystalV2::Compiler::Semantic::GeneratedOverlay.empty

    overlay.node_file_paths.should be_empty
    overlay.top_level_roots.should be_empty
    overlay.root_sources.should be_empty
    overlay.root_by_node.should be_empty
    overlay.root_origins.should be_empty
    overlay.root_macro_defs.should be_empty
  end

  it "duplicates overlay collections defensively" do
    root_id = CrystalV2::Compiler::Frontend::ExprId.new(10)
    node_id = CrystalV2::Compiler::Frontend::ExprId.new(12)
    origin_id = CrystalV2::Compiler::Frontend::ExprId.new(4)
    macro_def_id = CrystalV2::Compiler::Frontend::ExprId.new(1)

    overlay = CrystalV2::Compiler::Semantic::GeneratedOverlay.new(
      {10 => "/tmp/main.cr", 12 => "/tmp/main.cr"},
      [root_id],
      {10 => "def alpha\nend\n"},
      {12 => 10},
      {10 => origin_id},
      {10 => macro_def_id},
    )

    copy = overlay.dup
    copy.node_file_paths[10] = "/tmp/other.cr"
    copy.top_level_roots << CrystalV2::Compiler::Frontend::ExprId.new(99)
    copy.root_sources[10] = "changed"
    copy.root_by_node[12] = 11
    copy.root_origins[10] = CrystalV2::Compiler::Frontend::ExprId.new(7)
    copy.root_macro_defs[10] = CrystalV2::Compiler::Frontend::ExprId.new(8)

    overlay.node_file_paths[10].should eq("/tmp/main.cr")
    overlay.top_level_roots.should eq([root_id])
    overlay.root_sources[10].should eq("def alpha\nend\n")
    overlay.root_by_node[12].should eq(10)
    overlay.root_origins[10].should eq(origin_id)
    overlay.root_macro_defs[10].should eq(macro_def_id)
  end
end
