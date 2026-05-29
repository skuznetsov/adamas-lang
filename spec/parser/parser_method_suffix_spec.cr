require "spec"

require "../../src/compiler/frontend/parser"


describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 43: Method name suffixes (? and !) (PRODUCTION-READY)" do
    it "parses method definition with ? suffix" do
      source = <<-CRYSTAL
      def empty?
        true
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      method_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(method_node).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      Adamas::Compiler::Frontend.node_def_name(method_node).not_nil!.should eq("empty?".to_slice)
    end

    it "parses method definition with ! suffix" do
      source = <<-CRYSTAL
      def save!
        42
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      method_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(method_node).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      Adamas::Compiler::Frontend.node_def_name(method_node).not_nil!.should eq("save!".to_slice)
    end

    it "parses bare method call with ? suffix as identifier" do
      source = <<-CRYSTAL
      empty?
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      # Bare call parses as Identifier (semantic analysis determines it's a call)
      id_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(id_node).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      Adamas::Compiler::Frontend.node_literal(id_node).not_nil!.should eq("empty?".to_slice)
    end

    it "parses bare method call with ! suffix as identifier" do
      source = <<-CRYSTAL
      save!
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      # Bare call parses as Identifier (semantic analysis determines it's a call)
      id_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(id_node).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      Adamas::Compiler::Frontend.node_literal(id_node).not_nil!.should eq("save!".to_slice)
    end

    it "parses method call with ! suffix and parentheses" do
      source = <<-CRYSTAL
      save!()
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      # With parentheses, parses as Call
      call_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call_node).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      callee_id = Adamas::Compiler::Frontend.node_callee(call_node).not_nil!
      callee = arena[callee_id]
      Adamas::Compiler::Frontend.node_kind(callee).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      Adamas::Compiler::Frontend.node_literal(callee).not_nil!.should eq("save!".to_slice)
    end

    it "parses method with ? suffix in class" do
      source = <<-CRYSTAL
      class Array
        def empty?
          size == 0
        end
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      class_node = arena[program.roots[0]]
      class_body = Adamas::Compiler::Frontend.node_class_body(class_node).not_nil!
      method_node = arena[class_body[0]]

      Adamas::Compiler::Frontend.node_kind(method_node).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      Adamas::Compiler::Frontend.node_def_name(method_node).not_nil!.should eq("empty?".to_slice)
    end

    it "parses method with ! suffix and parameters" do
      source = <<-CRYSTAL
      def update!(name, age)
        @name = name
        @age = age
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      method_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(method_node).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      Adamas::Compiler::Frontend.node_def_name(method_node).not_nil!.should eq("update!".to_slice)

      params = Adamas::Compiler::Frontend.node_def_params(method_node).not_nil!
      params.size.should eq(2)
      params[0].name.should eq("name".to_slice)
      params[1].name.should eq("age".to_slice)
    end

    it "parses member access with ? suffix" do
      source = <<-CRYSTAL
      obj.nil?()
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call_node).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      callee_id = Adamas::Compiler::Frontend.node_callee(call_node).not_nil!
      callee = arena[callee_id]
      Adamas::Compiler::Frontend.node_kind(callee).should eq(Adamas::Compiler::Frontend::NodeKind::MemberAccess)
      Adamas::Compiler::Frontend.node_member(callee).not_nil!.should eq("nil?".to_slice)
    end

    it "parses member access with ! suffix" do
      source = <<-CRYSTAL
      user.save!()
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call_node).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      callee_id = Adamas::Compiler::Frontend.node_callee(call_node).not_nil!
      callee = arena[callee_id]
      Adamas::Compiler::Frontend.node_kind(callee).should eq(Adamas::Compiler::Frontend::NodeKind::MemberAccess)
      Adamas::Compiler::Frontend.node_member(callee).not_nil!.should eq("save!".to_slice)
    end

    it "parses chained method calls with suffixes" do
      source = <<-CRYSTAL
      user.valid?().to_s()
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      # Top level is call to to_s
      to_s_call = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(to_s_call).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      to_s_member_id = Adamas::Compiler::Frontend.node_callee(to_s_call).not_nil!
      to_s_member = arena[to_s_member_id]
      Adamas::Compiler::Frontend.node_kind(to_s_member).should eq(Adamas::Compiler::Frontend::NodeKind::MemberAccess)
      Adamas::Compiler::Frontend.node_member(to_s_member).not_nil!.should eq("to_s".to_slice)

      # Left of to_s member access is call to valid?
      valid_call = arena[Adamas::Compiler::Frontend.node_left(to_s_member).not_nil!]
      Adamas::Compiler::Frontend.node_kind(valid_call).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      valid_member_id = Adamas::Compiler::Frontend.node_callee(valid_call).not_nil!
      valid_member = arena[valid_member_id]
      Adamas::Compiler::Frontend.node_kind(valid_member).should eq(Adamas::Compiler::Frontend::NodeKind::MemberAccess)
      Adamas::Compiler::Frontend.node_member(valid_member).not_nil!.should eq("valid?".to_slice)
    end

    it "parses method with ? suffix and type annotation" do
      source = <<-CRYSTAL
      def empty? : Bool
        true
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      method_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(method_node).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      Adamas::Compiler::Frontend.node_def_name(method_node).not_nil!.should eq("empty?".to_slice)

      return_type = Adamas::Compiler::Frontend.node_def_return_type(method_node)
      return_type.should_not be_nil
      return_type.not_nil!.should eq("Bool".to_slice)
    end

    it "parses multiple methods with different suffixes" do
      source = <<-CRYSTAL
      def valid?
        true
      end

      def save!
        42
      end

      def process
        1
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(3)
      arena = program.arena

      # First method: valid?
      method1 = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(method1).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      Adamas::Compiler::Frontend.node_def_name(method1).not_nil!.should eq("valid?".to_slice)

      # Second method: save!
      method2 = arena[program.roots[1]]
      Adamas::Compiler::Frontend.node_kind(method2).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      Adamas::Compiler::Frontend.node_def_name(method2).not_nil!.should eq("save!".to_slice)

      # Third method: process (no suffix)
      method3 = arena[program.roots[2]]
      Adamas::Compiler::Frontend.node_kind(method3).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      Adamas::Compiler::Frontend.node_def_name(method3).not_nil!.should eq("process".to_slice)
    end

    it "parses method call with ! suffix and arguments" do
      source = <<-CRYSTAL
      delete!(key, value)
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call_node).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      callee_id = Adamas::Compiler::Frontend.node_callee(call_node).not_nil!
      callee = arena[callee_id]
      Adamas::Compiler::Frontend.node_kind(callee).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
      Adamas::Compiler::Frontend.node_literal(callee).not_nil!.should eq("delete!".to_slice)

      args = Adamas::Compiler::Frontend.node_args(call_node).not_nil!
      args.size.should eq(2)
    end
  end
end
