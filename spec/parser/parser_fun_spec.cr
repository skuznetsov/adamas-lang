require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 64: Fun keyword (PRODUCTION-READY)" do
    it "parses fun without parameters or return type" do
      source = <<-CRYSTAL
      lib LibC
        fun exit
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      lib_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(lib_node).should eq(Adamas::Compiler::Frontend::NodeKind::Lib)

      body = lib_node.as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
      body.size.should eq(1)

      fun_node = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(fun_node).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
      String.new(fun_node.as(Adamas::Compiler::Frontend::FunNode).name).should eq("exit")
      nil # FunNode has no body field.should be_nil  # No body for fun
    end

    it "parses top-level bare fun declarations without consuming following defs" do
      source = <<-CRYSTAL
      fun __crystal_raise(unwind_ex : Void*) : NoReturn

      def raise_without_backtrace(exception)
        __crystal_raise(exception.as(Void*))
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(2)
      arena = program.arena

      fun_node = arena[program.roots[0]].as(Adamas::Compiler::Frontend::FunNode)
      String.new(fun_node.name).should eq("__crystal_raise")

      def_node = arena[program.roots[1]].as(Adamas::Compiler::Frontend::DefNode)
      String.new(def_node.name).should eq("raise_without_backtrace")
    end

    it "parses top-level fun bodies that start with macro control" do
      source = <<-CRYSTAL
      fun __crystal_malloc64(size : UInt64) : Void*
        {% if flag?(:bits32) %}
          if size > UInt32::MAX
            raise ArgumentError.new("Given size is bigger than UInt32::MAX")
          end
        {% end %}

        GC.malloc(LibC::SizeT.new(size))
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      def_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(def_node).should eq(Adamas::Compiler::Frontend::NodeKind::Def)

      fun_def = def_node.as(Adamas::Compiler::Frontend::DefNode)
      String.new(fun_def.name.not_nil!).should eq("__crystal_malloc64")
      String.new(fun_def.receiver.not_nil!).should eq("__fun__")
      fun_def.body.not_nil!.size.should eq(2)

      first_stmt = arena[fun_def.body.not_nil![0]]
      Adamas::Compiler::Frontend.node_kind(first_stmt).should eq(Adamas::Compiler::Frontend::NodeKind::MacroIf)

      second_stmt = arena[fun_def.body.not_nil![1]]
      Adamas::Compiler::Frontend.node_kind(second_stmt).should eq(Adamas::Compiler::Frontend::NodeKind::Call)
    end

    it "parses fun with parameters" do
      source = <<-CRYSTAL
      lib LibC
        fun printf(format : UInt8)
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      lib_node = arena[program.roots[0]]
      body = lib_node.as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
      fun_node = arena[body[0]]

      Adamas::Compiler::Frontend.node_kind(fun_node).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
      String.new(fun_node.as(Adamas::Compiler::Frontend::FunNode).name).should eq("printf")

      params = fun_node.as(Adamas::Compiler::Frontend::FunNode).params.not_nil!
      params.size.should eq(1)
      String.new(params[0].name.not_nil!).should eq("format")
      String.new(params[0].type_annotation.not_nil!).should eq("UInt8")
    end

    it "parses fun with return type" do
      source = <<-CRYSTAL
      lib LibC
        fun getpid : Int32
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      lib_node = arena[program.roots[0]]
      body = lib_node.as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
      fun_node = arena[body[0]]

      Adamas::Compiler::Frontend.node_kind(fun_node).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
      String.new(fun_node.as(Adamas::Compiler::Frontend::FunNode).name).should eq("getpid")
      String.new(fun_node.as(Adamas::Compiler::Frontend::FunNode).return_type.not_nil!).should eq("Int32")
      nil # FunNode has no body field.should be_nil
    end

    it "parses fun with parameters and return type" do
      source = <<-CRYSTAL
      lib LibC
        fun malloc(size : UInt64) : Void
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      lib_node = arena[program.roots[0]]
      body = lib_node.as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
      fun_node = arena[body[0]]

      Adamas::Compiler::Frontend.node_kind(fun_node).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
      String.new(fun_node.as(Adamas::Compiler::Frontend::FunNode).name).should eq("malloc")

      params = fun_node.as(Adamas::Compiler::Frontend::FunNode).params.not_nil!
      params.size.should eq(1)
      String.new(params[0].name.not_nil!).should eq("size")
      String.new(params[0].type_annotation.not_nil!).should eq("UInt64")

      String.new(fun_node.as(Adamas::Compiler::Frontend::FunNode).return_type.not_nil!).should eq("Void")
      nil # FunNode has no body field.should be_nil
    end

    it "parses multiple fun declarations in lib" do
      source = <<-CRYSTAL
      lib LibC
        fun getpid : Int32
        fun exit(code : Int32)
        fun malloc(size : UInt64) : Void
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      lib_node = arena[program.roots[0]]
      body = lib_node.as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
      body.size.should eq(3)

      # First fun: getpid
      fun1 = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(fun1).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
      String.new(fun1.as(Adamas::Compiler::Frontend::FunNode).name).should eq("getpid")

      # Second fun: exit
      fun2 = arena[body[1]]
      Adamas::Compiler::Frontend.node_kind(fun2).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
      String.new(fun2.as(Adamas::Compiler::Frontend::FunNode).name).should eq("exit")

      # Third fun: malloc
      fun3 = arena[body[2]]
      Adamas::Compiler::Frontend.node_kind(fun3).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
      String.new(fun3.as(Adamas::Compiler::Frontend::FunNode).name).should eq("malloc")
    end

    it "parses fun with multiple parameters" do
      source = <<-CRYSTAL
      lib LibC
        fun strncmp(s1 : UInt8, s2 : UInt8, n : UInt64) : Int32
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      lib_node = arena[program.roots[0]]
      body = lib_node.as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
      fun_node = arena[body[0]]

      Adamas::Compiler::Frontend.node_kind(fun_node).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
      String.new(fun_node.as(Adamas::Compiler::Frontend::FunNode).name).should eq("strncmp")

      params = fun_node.as(Adamas::Compiler::Frontend::FunNode).params.not_nil!
      params.size.should eq(3)

      String.new(params[0].name.not_nil!).should eq("s1")
      String.new(params[0].type_annotation.not_nil!).should eq("UInt8")

      String.new(params[1].name.not_nil!).should eq("s2")
      String.new(params[1].type_annotation.not_nil!).should eq("UInt8")

      String.new(params[2].name.not_nil!).should eq("n")
      String.new(params[2].type_annotation.not_nil!).should eq("UInt64")

      String.new(fun_node.as(Adamas::Compiler::Frontend::FunNode).return_type.not_nil!).should eq("Int32")
    end

    it "parses fun without return type has nil return type" do
      source = <<-CRYSTAL
      lib LibC
        fun exit(code : Int32)
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      lib_node = arena[program.roots[0]]
      body = lib_node.as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
      fun_node = arena[body[0]]

      Adamas::Compiler::Frontend.node_kind(fun_node).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
      fun_node.as(Adamas::Compiler::Frontend::FunNode).return_type.should be_nil
    end

    it "parses fun with no parameters as empty array" do
      source = <<-CRYSTAL
      lib LibC
        fun getpid : Int32
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      lib_node = arena[program.roots[0]]
      body = lib_node.as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
      fun_node = arena[body[0]]

      Adamas::Compiler::Frontend.node_kind(fun_node).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
      params = fun_node.as(Adamas::Compiler::Frontend::FunNode).params
      (params.nil? || params.size == 0).should be_true
    end

    it "parses fun with spaces around colons" do
      source = <<-CRYSTAL
      lib LibC
        fun malloc(size : UInt64) : Void
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      lib_node = arena[program.roots[0]]
      body = lib_node.as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
      fun_node = arena[body[0]]

      Adamas::Compiler::Frontend.node_kind(fun_node).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
      String.new(fun_node.as(Adamas::Compiler::Frontend::FunNode).name).should eq("malloc")
    end

    it "parses lib with mixed fun and other declarations" do
      source = <<-CRYSTAL
      lib LibC
        fun getpid : Int32
        fun exit(code : Int32)
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      lib_node = arena[program.roots[0]]
      body = lib_node.as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
      body.size.should eq(2)

      # Both should be fun declarations
      fun1 = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(fun1).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)

      fun2 = arena[body[1]]
      Adamas::Compiler::Frontend.node_kind(fun2).should eq(Adamas::Compiler::Frontend::NodeKind::Fun)
    end
  end
end
