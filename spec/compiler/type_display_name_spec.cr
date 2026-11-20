require "spec"
require "../../src/compiler/type_display_name"

describe Adamas::TypeDisplayName do
  it "moves Nil to the end of every union, including generic arguments" do
    Adamas::TypeDisplayName.crystal("Nil | Int32").should eq("Int32 | Nil")
    Adamas::TypeDisplayName.crystal("(Nil | Char | Float64)").should eq("(Char | Float64 | Nil)")
    Adamas::TypeDisplayName.crystal("Array(Nil | Int32)").should eq("Array(Int32 | Nil)")
    Adamas::TypeDisplayName.crystal("Hash(String, Array(Nil | String))").should eq("Hash(String, Array(String | Nil))")
    Adamas::TypeDisplayName.crystal("NamedTuple(a: Nil | Int32, b: String)").should eq("NamedTuple(a: Int32 | Nil, b: String)")
    Adamas::TypeDisplayName.crystal("Array(Array(Nil | String)) | Nil").should eq("Array(Array(String | Nil)) | Nil")
  end

  it "drops root anchors" do
    Adamas::TypeDisplayName.crystal("Array(::Int32 | ::Nil)").should eq("Array(Int32 | Nil)")
    Adamas::TypeDisplayName.crystal("::Foo::Bar").should eq("Foo::Bar")
    Adamas::TypeDisplayName.crystal("(::Nil | ::Foo::Baz)").should eq("(Foo::Baz | Nil)")
  end

  it "keeps other names and member order unchanged" do
    Adamas::TypeDisplayName.crystal("Zeta | Alpha").should eq("Zeta | Alpha")
    Adamas::TypeDisplayName.crystal("Proc(Int32, Nil)").should eq("Proc(Int32, Nil)")
    Adamas::TypeDisplayName.crystal("NilClass | Int32").should eq("NilClass | Int32")
    Adamas::TypeDisplayName.crystal("Foo::Bar").should eq("Foo::Bar")
    Adamas::TypeDisplayName.crystal("Nil").should eq("Nil")
  end
end
