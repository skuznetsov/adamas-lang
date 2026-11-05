require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_force_publication_frame(completed : Bool, &)
    frame = ForceLowerPublicationFrame.new
    @force_lower_publication_frames << frame
    begin
      yield
    ensure
      @force_lower_publication_frames.pop
      finish_force_lower_publication_frame(frame, completed)
    end
  end

  def __test_force_publish(name : String, type : TypeRef, publish_base : Bool = true)
    register_function_type(name, type, allow_explicit_replacement: true)
    set_function_base_return_type(name, type) if publish_base
  end

  def __test_force_published_types(name : String)
    {@function_types[name]?, @function_base_return_types[name]?}
  end
end

private def force_publication_fixture
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
  program = parser.parse_program
  Adamas::HIR::AstToHir.new(program.arena)
end

describe "forced generation return publication ownership" do
  it "retracts only writes of the aborted generation" do
    converter = force_publication_fixture
    converter.__test_force_publish("prior", Adamas::HIR::TypeRef::INT32)
    converter.__test_force_publication_frame(false) do
      converter.__test_force_publish("prior", Adamas::HIR::TypeRef::INT64)
      converter.__test_force_publish("new", Adamas::HIR::TypeRef::BOOL)
    end
    converter.__test_force_published_types("prior").should eq({Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32})
    converter.__test_force_published_types("new").should eq({nil, nil})
  end

  it "retains a completed grandchild through both aborted ancestors" do
    converter = force_publication_fixture
    converter.__test_force_publish("shared", Adamas::HIR::TypeRef::INT32)
    converter.__test_force_publication_frame(false) do
      converter.__test_force_publish("shared", Adamas::HIR::TypeRef::INT64)
      converter.__test_force_publication_frame(false) do
        converter.__test_force_publish("shared", Adamas::HIR::TypeRef::BOOL)
        converter.__test_force_publication_frame(true) do
          converter.__test_force_publish("shared", Adamas::HIR::TypeRef::UINT32)
        end
      end
    end
    converter.__test_force_published_types("shared").should eq({Adamas::HIR::TypeRef::UINT32, Adamas::HIR::TypeRef::UINT32})
  end

  it "restores the completed child's baseline after a later parent write" do
    converter = force_publication_fixture
    converter.__test_force_publication_frame(false) do
      converter.__test_force_publish("shared", Adamas::HIR::TypeRef::INT32)
      converter.__test_force_publication_frame(true) do
        converter.__test_force_publish("shared", Adamas::HIR::TypeRef::BOOL)
      end
      converter.__test_force_publish("shared", Adamas::HIR::TypeRef::INT64)
    end
    converter.__test_force_published_types("shared").should eq({Adamas::HIR::TypeRef::BOOL, Adamas::HIR::TypeRef::BOOL})
  end

  it "retains a completed child's publication when its type equals the parent's" do
    converter = force_publication_fixture
    converter.__test_force_publication_frame(false) do
      converter.__test_force_publish("shared", Adamas::HIR::TypeRef::INT32)
      converter.__test_force_publication_frame(true) do
        converter.__test_force_publish("shared", Adamas::HIR::TypeRef::INT32)
      end
    end
    converter.__test_force_published_types("shared").should eq({Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32})
  end

  it "retains the equal base contract through the registry's unchanged-type path" do
    converter = force_publication_fixture
    converter.__test_force_publication_frame(false) do
      converter.__test_force_publish("shared", Adamas::HIR::TypeRef::INT32)
      converter.__test_force_publication_frame(true) do
        converter.__test_force_publish("shared", Adamas::HIR::TypeRef::INT32, publish_base: false)
      end
    end
    converter.__test_force_published_types("shared").should eq({Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32})
  end
end
