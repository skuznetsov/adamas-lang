require "../spec_helper"
require "../../src/compiler/hir/hir"

describe Adamas::HIR do
  describe "LifetimeTag" do
    it "compares correctly" do
      Adamas::HIR::LifetimeTag::HeapEscape.escapes_more_than?(Adamas::HIR::LifetimeTag::StackLocal).should be_true
      Adamas::HIR::LifetimeTag::StackLocal.escapes_more_than?(Adamas::HIR::LifetimeTag::HeapEscape).should be_false
    end

    it "merges to most escaped" do
      Adamas::HIR::LifetimeTag::StackLocal.merge(Adamas::HIR::LifetimeTag::HeapEscape).should eq(Adamas::HIR::LifetimeTag::HeapEscape)
      Adamas::HIR::LifetimeTag::GlobalEscape.merge(Adamas::HIR::LifetimeTag::ArgEscape).should eq(Adamas::HIR::LifetimeTag::GlobalEscape)
    end
  end

  describe "TypeRef" do
    it "has primitive types" do
      Adamas::HIR::TypeRef::INT32.primitive?.should be_true
      Adamas::HIR::TypeRef::STRING.primitive?.should be_true
    end

    it "compares by id" do
      (Adamas::HIR::TypeRef::INT32 == Adamas::HIR::TypeRef::INT32).should be_true
      (Adamas::HIR::TypeRef::INT32 == Adamas::HIR::TypeRef::INT64).should be_false
    end
  end

  describe "Module" do
    it "creates empty module" do
      mod = Adamas::HIR::Module.new("test")
      mod.name.should eq("test")
      mod.functions.size.should eq(0)
    end

    it "interns strings" do
      mod = Adamas::HIR::Module.new
      id1 = mod.intern_string("hello")
      id2 = mod.intern_string("world")
      id3 = mod.intern_string("hello")

      id1.should eq(id3)  # Same string = same ID
      id1.should_not eq(id2)
      mod.strings.size.should eq(2)
    end

    it "creates function with entry block" do
      mod = Adamas::HIR::Module.new
      func = mod.create_function("foo", Adamas::HIR::TypeRef::VOID)

      func.name.should eq("foo")
      func.blocks.size.should eq(1)  # Entry block
      func.scopes.size.should eq(1)  # Function scope
    end

    it "removes and re-adds one canonical function across every registry" do
      mod = Adamas::HIR::Module.new
      removed = mod.create_function("Owner#work$Int32", Adamas::HIR::TypeRef::INT32)
      retained = mod.create_function("Owner#work$String", Adamas::HIR::TypeRef::STRING)

      dynamic_name = String.build { |io| io << "Owner#work$Int32" }
      mod.remove_function(dynamic_name).should be_true

      mod.function_count.should eq(1)
      mod.function_by_name("Owner#work$Int32").should be_nil
      mod.functions.should eq([retained])
      mod.functions_by_base_name("Owner#work").should eq([retained])
      mod.remove_function("Owner#work$Int32").should be_false

      replacement = mod.create_function(dynamic_name, Adamas::HIR::TypeRef::INT32)
      replacement.same?(removed).should be_false
      mod.create_function("Owner#work$Int32", Adamas::HIR::TypeRef::INT32)
        .same?(replacement).should be_true
      mod.function_count.should eq(2)
      mod.functions_by_base_name("Owner#work").not_nil!.size.should eq(2)
    end

    it "keeps canonical identity across a high-cardinality remove and re-add" do
      mod = Adamas::HIR::Module.new
      names = Array(String).new(768) do |index|
        String.build { |io| io << "Owner#work$Fn" << index }
      end
      original = names.map { |name| mod.create_function(name, Adamas::HIR::TypeRef::VOID) }

      mod.function_count.should eq(768)
      names.each_with_index do |name, index|
        next if index.odd?
        mod.remove_function(name).should be_true
      end
      mod.function_count.should eq(384)

      names.each_with_index do |name, index|
        if index.odd?
          mod.function_by_name(name).not_nil!.same?(original[index]).should be_true
        else
          mod.function_by_name(name).should be_nil
        end
      end

      canonical = original.dup
      names.each_with_index do |name, index|
        next if index.odd?
        replacement = mod.create_function(name, Adamas::HIR::TypeRef::VOID)
        replacement.same?(original[index]).should be_false
        canonical[index] = replacement
      end
      mod.function_count.should eq(768)

      names.each_with_index do |name, index|
        mod.function_by_name(name).not_nil!.same?(canonical[index]).should be_true
        mod.create_function(name, Adamas::HIR::TypeRef::VOID).same?(canonical[index]).should be_true
      end
      mod.function_count.should eq(768)
    end

    it "includes virtual call targets by base name" do
      mod = Adamas::HIR::Module.new
      main = mod.create_function("__adamas_main", Adamas::HIR::TypeRef::VOID)
      receiver = main.add_param("self", Adamas::HIR::TypeRef::POINTER)

      call = Adamas::HIR::Call.new(
        1_u32,
        Adamas::HIR::TypeRef::VOID,
        receiver.id,
        "A#foo",
        [] of Adamas::HIR::ValueId,
        nil,
        true
      )
      main.blocks[0].add(call)

      # Register B as subclass of A, so virtual call to A#foo reaches B#foo
      mod.class_parents["B"] = "A"

      # RTA needs types to be instantiated (via Allocate) to include them
      a_type_ref = mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "A"))
      b_type_ref = mod.intern_type(Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "B"))
      alloc_a = Adamas::HIR::Allocate.new(2_u32, a_type_ref)
      alloc_b = Adamas::HIR::Allocate.new(3_u32, b_type_ref)
      main.blocks[0].add(alloc_a)
      main.blocks[0].add(alloc_b)

      mod.create_function("A#foo", Adamas::HIR::TypeRef::VOID)
      mod.create_function("B#foo", Adamas::HIR::TypeRef::VOID)
      mod.create_function("C#bar", Adamas::HIR::TypeRef::VOID)

      reachable = mod.reachable_function_names(["__adamas_main"])
      reachable.should contain("A#foo")
      reachable.should contain("B#foo")
      reachable.should_not contain("C#bar")
    end

    it "normalizes only synthetic super callees during reachability" do
      mod = Adamas::HIR::Module.new
      main = mod.create_function("__adamas_main", Adamas::HIR::TypeRef::VOID)
      main.blocks[0].add(Adamas::HIR::Call.without_receiver(
        1_u32,
        Adamas::HIR::TypeRef::VOID,
        "Parent#foo_super",
        [] of Adamas::HIR::ValueId,
      ))
      main.blocks[0].add(Adamas::HIR::Call.without_receiver(
        2_u32,
        Adamas::HIR::TypeRef::VOID,
        "Special#bar_super",
        [] of Adamas::HIR::ValueId,
      ))

      mod.create_function("Parent#foo", Adamas::HIR::TypeRef::VOID)
      mod.create_function("Special#bar", Adamas::HIR::TypeRef::VOID)
      mod.create_function("Special#bar_super", Adamas::HIR::TypeRef::VOID)

      reachable = mod.reachable_function_names(["__adamas_main"])
      reachable.should contain("Parent#foo")
      reachable.should contain("Special#bar_super")
      reachable.should_not contain("Special#bar")
    end
  end

  describe "Function" do
    it "adds parameters" do
      mod = Adamas::HIR::Module.new
      func = mod.create_function("add", Adamas::HIR::TypeRef::INT32)

      param_a = func.add_param("a", Adamas::HIR::TypeRef::INT32)
      param_b = func.add_param("b", Adamas::HIR::TypeRef::INT32)

      func.params.size.should eq(2)
      param_a.name.should eq("a")
      param_a.index.should eq(0)
      param_b.index.should eq(1)
    end

    it "creates blocks and scopes" do
      mod = Adamas::HIR::Module.new
      func = mod.create_function("test", Adamas::HIR::TypeRef::VOID)

      # Entry block already exists
      func.blocks.size.should eq(1)

      # Create nested scope and block
      inner_scope = func.create_scope(Adamas::HIR::ScopeKind::Block, parent: 0_u32)
      inner_block = func.create_block(inner_scope)

      func.scopes.size.should eq(2)
      func.blocks.size.should eq(2)
      func.get_scope(inner_scope).parent.should eq(0_u32)
    end
  end

  describe "Values" do
    it "creates literal" do
      lit = Adamas::HIR::Literal.new(0_u32, Adamas::HIR::TypeRef::INT64, 42_i64)
      lit.value.should eq(42_i64)
      lit.lifetime.should eq(Adamas::HIR::LifetimeTag::StackLocal)
    end

    it "creates allocate" do
      user_type = Adamas::HIR::TypeRef.new(100_u32)
      alloc = Adamas::HIR::Allocate.new(0_u32, user_type)
      alloc.type.should eq(user_type)
      alloc.lifetime.should eq(Adamas::HIR::LifetimeTag::Unknown)
    end

    it "creates call" do
      call = Adamas::HIR::Call.new(
        id: 0_u32,
        type: Adamas::HIR::TypeRef::INT32,
        receiver: 1_u32,
        method_name: "foo",
        args: [2_u32, 3_u32]
      )
      call.method_name.should eq("foo")
      call.args.size.should eq(2)
    end

    it "creates closure with captures" do
      captures = [
        Adamas::HIR::CapturedVar.new(1_u32, "x", by_reference: true),
        Adamas::HIR::CapturedVar.new(2_u32, "y", by_reference: false),
      ]
      closure = Adamas::HIR::MakeClosure.new(0_u32, Adamas::HIR::TypeRef.new(50_u32), 5_u32, captures)

      closure.captures.size.should eq(2)
      closure.captures[0].by_reference.should be_true
      closure.captures[1].by_reference.should be_false
      closure.lifetime.should eq(Adamas::HIR::LifetimeTag::HeapEscape)
    end
  end

  describe "Terminators" do
    it "return has no successors" do
      ret = Adamas::HIR::Return.new(0_u32)
      ret.successors.should eq([] of Adamas::HIR::BlockId)
    end

    it "branch has two successors" do
      branch = Adamas::HIR::Branch.new(0_u32, 1_u32, 2_u32)
      branch.successors.should eq([1_u32, 2_u32])
    end

    it "jump has one successor" do
      jump = Adamas::HIR::Jump.new(5_u32)
      jump.successors.should eq([5_u32])
    end

    it "switch has multiple successors" do
      switch = Adamas::HIR::Switch.new(0_u32, [{1_u32, 2_u32}, {3_u32, 4_u32}], 5_u32)
      switch.successors.should eq([2_u32, 4_u32, 5_u32])
    end
  end

  describe "Block" do
    it "adds instructions" do
      block = Adamas::HIR::Block.new(0_u32, 0_u32)

      lit = Adamas::HIR::Literal.new(0_u32, Adamas::HIR::TypeRef::INT32, 1_i64)
      block.add(lit)

      block.instructions.size.should eq(1)
    end

    it "has default unreachable terminator" do
      block = Adamas::HIR::Block.new(0_u32, 0_u32)
      block.terminator.should be_a(Adamas::HIR::Unreachable)
    end
  end

  describe "Text output" do
    it "prints simple function" do
      mod = Adamas::HIR::Module.new("test")
      func = mod.create_function("add", Adamas::HIR::TypeRef::INT32)

      param_a = func.add_param("a", Adamas::HIR::TypeRef::INT32)
      param_b = func.add_param("b", Adamas::HIR::TypeRef::INT32)

      entry = func.get_block(func.entry_block)

      # %2 = binop Add %0, %1
      binop = Adamas::HIR::BinaryOperation.new(
        func.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        Adamas::HIR::BinaryOp::Add,
        param_a.id,
        param_b.id
      )
      entry.add(binop)
      entry.terminator = Adamas::HIR::Return.new(binop.id)

      output = String.build { |io| mod.to_s(io) }

      output.should contain("func @add")
      output.should contain("binop Add")
      output.should contain("return %2")
    end
  end
end
