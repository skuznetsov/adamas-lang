require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_resolve_enum_name_with(enums : Hash(String, Hash(String, Int64)), name : String) : String?
    @enum_info = enums
    resolve_enum_name(name)
  end
end

private def union_spelling_enum_converter
  Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
end

private def union_spelling_enums
  {"Sys::Errno" => {"A" => 0_i64, "B" => 1_i64}}
end

describe "Enum name resolution of union spellings" do
  it "resolves the enum's own and short spellings" do
    union_spelling_enum_converter.__test_resolve_enum_name_with(union_spelling_enums, "Sys::Errno").should eq("Sys::Errno")
    union_spelling_enum_converter.__test_resolve_enum_name_with(union_spelling_enums, "Errno").should eq("Sys::Errno")
  end

  # `{FD::Handle, Bool} | Errno` is EventLoop#open's return type. Its last
  # namespace component is `Errno`, so the suffix fallback tagged the
  # union-returning call as the enum.
  it "never reads a union whose last arm is the enum as that enum" do
    union_spelling_enum_converter.__test_resolve_enum_name_with(union_spelling_enums, "Tuple(Int32, Bool) | Sys::Errno").should be_nil
    union_spelling_enum_converter.__test_resolve_enum_name_with(union_spelling_enums, "Int32 | Sys::Errno").should be_nil
  end

  it "never reads a union whose first arm is the enum as that enum" do
    union_spelling_enum_converter.__test_resolve_enum_name_with(union_spelling_enums, "Sys::Errno | Int32").should be_nil
  end

  # `property strategy : Strategy?` keeps the enum identity of its non-Nil
  # arm (the getter's carrier is `Int32 | Nil`).
  it "reads a nilable enum spelling in either order as that enum" do
    union_spelling_enum_converter.__test_resolve_enum_name_with(union_spelling_enums, "Nil | Sys::Errno").should eq("Sys::Errno")
    union_spelling_enum_converter.__test_resolve_enum_name_with(union_spelling_enums, "Sys::Errno | Nil").should eq("Sys::Errno")
    union_spelling_enum_converter.__test_resolve_enum_name_with(union_spelling_enums, "Errno | Nil").should eq("Sys::Errno")
  end

  it "never reads a nilable union of several arms as the enum" do
    union_spelling_enum_converter.__test_resolve_enum_name_with(union_spelling_enums, "Int32 | Nil | Sys::Errno").should be_nil
    union_spelling_enum_converter.__test_resolve_enum_name_with(union_spelling_enums, "Nil | Int32").should be_nil
  end
end
