require "spec"
require "../../src/compiler/semantic/identity/semantic_type_id"
require "../../src/compiler/semantic/identity/def_identity"
require "../../src/compiler/semantic/identity/def_instance_key"
require "../../src/compiler/semantic/identity/name_id"

module IdentitySpec
  include Adamas::Compiler::Semantic

  # Test-only seams set the private next ordinal directly, avoiding billions
  # of allocations while exercising the reserved UNKNOWN boundary.
  class NameInternTableOverflowProbe < NameInternTable
    def set_next_id_for_test(value : UInt32) : Nil
      @next_id = value
    end
  end

  class SemanticTypeInternTableOverflowProbe < SemanticTypeInternTable
    def set_next_id_for_test(value : UInt32) : Nil
      @next_id = value
    end
  end

  # ── SemanticTypeId ──

  describe "SemanticTypeId" do
    it "canonical equality within one interner" do
      table = SemanticTypeInternTable.new
      a = table.primitive("Int32")
      b = table.primitive("Int32")
      c = table.primitive("String")
      (a == b).should be_true
      (a == c).should be_false
    end

    it "raw ordinals are non-authoritative" do
      a = SemanticTypeId.new(7_u32)
      b = SemanticTypeId.new(7_u32)
      a.should eq b
      a.hash.should eq b.hash

      names = NameInternTable.new
      table = SemanticTypeInternTable.new(names)
      name_id = names.intern("Array")
      expect_raises(ArgumentError) do
        table.intern(SemanticTypeKey.new(TypeKind::Array, name_id, [a]))
      end
      table.lookup(a).should be_nil
      table.normalized_name(a).should eq "Unknown"
    end

    it "hash stability — same canonical id always same hash" do
      table = SemanticTypeInternTable.new
      a = table.primitive("Int32")
      b = table.primitive("Int32")
      a.hash.should eq b.hash
    end

    it "UNKNOWN sentinel" do
      SemanticTypeId::UNKNOWN.id.should eq UInt32::MAX
    end
  end

  # ── SemanticTypeInternTable ──

  describe "SemanticTypeInternTable" do
    it "interns same key to same id" do
      t = SemanticTypeInternTable.new
      a = t.primitive("Int32")
      b = t.primitive("Int32")
      (a == b).should be_true
      a.id.should eq b.id
    end

    it "different types get different ids" do
      t = SemanticTypeInternTable.new
      a = t.primitive("Int32")
      b = t.primitive("String")
      (a == b).should be_false
    end

    it "Union(A|B) == Union(B|A) — order independent" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      str = t.primitive("String")
      u1 = t.union([int, str])
      u2 = t.union([str, int])
      (u1 == u2).should be_true
      u1.id.should eq u2.id
    end

    it "Tuple(A,B) != Tuple(B,A) — order dependent" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      str = t.primitive("String")
      t1 = t.tuple([int, str])
      t2 = t.tuple([str, int])
      (t1 == t2).should be_false
    end

    it "generic with same params gets same id" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      a = t.generic("Array", TypeKind::Array, [int])
      b = t.generic("Array", TypeKind::Array, [int])
      (a == b).should be_true
    end

    it "generic with different params gets different id" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      str = t.primitive("String")
      a = t.generic("Array", TypeKind::Array, [int])
      b = t.generic("Array", TypeKind::Array, [str])
      (a == b).should be_false
    end

    it "proc_type interning" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      str = t.primitive("String")
      p1 = t.proc_type([int], str)
      p2 = t.proc_type([int], str)
      (p1 == p2).should be_true
    end

    it "pointer interning" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      a = t.pointer(int)
      b = t.pointer(int)
      (a == b).should be_true
    end

    it "normalized_name for primitives" do
      t = SemanticTypeInternTable.new
      id = t.primitive("Int32")
      t.normalized_name(id).should eq "Int32"
    end

    it "normalized_name for union is sorted alphabetically" do
      t = SemanticTypeInternTable.new
      str = t.primitive("String")
      int = t.primitive("Int32")
      u = t.union([str, int])
      t.normalized_name(u).should eq "Int32 | String"
    end

    it "normalized_name for generic" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      arr = t.generic("Array", TypeKind::Array, [int])
      t.normalized_name(arr).should eq "Array(Int32)"
    end

    it "normalized_name for proc" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      str = t.primitive("String")
      p = t.proc_type([int], str)
      t.normalized_name(p).should eq "Proc(Int32, String)"
    end

    it "normalized_name for tuple" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      str = t.primitive("String")
      tup = t.tuple([int, str])
      t.normalized_name(tup).should eq "Tuple(Int32, String)"
    end

    it "normalized_name for pointer" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      p = t.pointer(int)
      t.normalized_name(p).should eq "Pointer(Int32)"
    end

    it "size tracks unique types" do
      t = SemanticTypeInternTable.new
      t.primitive("Int32")
      t.primitive("String")
      t.primitive("Int32") # duplicate
      t.size.should eq 2
    end

    it "lookup reverse" do
      t = SemanticTypeInternTable.new
      id = t.primitive("Float64")
      key = t.lookup(id)
      key.should_not be_nil
      t.name_for(key.not_nil!.name_id).should eq "Float64"
      key.not_nil!.kind.should eq TypeKind::Primitive
    end

    it "owns type spelling input and diagnostic reverse storage" do
      t = SemanticTypeInternTable.new
      spelling = String.build { |io| io << "Int32" }
      id = t.primitive(spelling)
      spelling.to_unsafe[0] = 'X'.ord.to_u8

      reverse = t.name_for(t.lookup(id).not_nil!.name_id).not_nil!
      reverse.to_unsafe[0] = 'Y'.ord.to_u8

      t.primitive("Int32").should eq id
      t.normalized_name(id).should eq "Int32"
    end

    it "rejects reserved semantic type id ordinal without filling the table" do
      t = SemanticTypeInternTableOverflowProbe.new
      t.set_next_id_for_test(UInt32::MAX)
      expect_raises(Exception) do
        t.intern(SemanticTypeKey.new(TypeKind::Tuple, NameId::UNKNOWN, [] of SemanticTypeId))
      end
      t.size.should eq 0
    end

    it "owns generic components so caller mutation cannot remint identity" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      str = t.primitive("String")
      args = [int]
      id = t.generic("Array", TypeKind::Array, args)

      args << str

      t.generic("Array", TypeKind::Array, [int]).should eq id
      t.lookup(id).not_nil!.type_params.size.should eq 1
    end

    it "owns tuple components so caller mutation cannot change reverse lookup" do
      t = SemanticTypeInternTable.new
      int = t.primitive("Int32")
      str = t.primitive("String")
      elements = [int, str]
      id = t.tuple(elements)

      elements.reverse!

      t.tuple([int, str]).should eq id
      t.lookup(id).not_nil!.type_params.to_a.should eq [int, str]
    end

    it "keeps a semantic key stable as a Hash key after caller mutation" do
      int = SemanticTypeId.new(1_u32)
      str = SemanticTypeId.new(2_u32)
      params = [int]
      name_id = NameInternTable.new.intern("Array")
      key = SemanticTypeKey.new(TypeKind::Array, name_id, params)
      params << str

      keys = {} of SemanticTypeKey => Int32
      keys[key] = 7
      keys[key].should eq 7
      key.type_params.size.should eq 1
    end

    it "sorted component carriers do not borrow caller arrays" do
      table = SemanticTypeInternTable.new
      int = table.primitive("Int32")
      str = table.primitive("String")
      input = [str, int]
      components = SemanticTypeComponents.sorted_copy(input) { |id| id.id }
      before = components.hash

      input.reverse!

      components.hash.should eq before
      components.to_a.should eq [int, str]
    end

    it "keeps semantic type ordinals scoped to each interner" do
      left_table = SemanticTypeInternTable.new
      right_table = SemanticTypeInternTable.new
      left = left_table.primitive("Int32")
      right = right_table.primitive("Int32")

      left.should_not eq right
      ids = {} of SemanticTypeId => Int32
      ids[left] = 1
      ids[right] = 2
      ids.size.should eq 2
      left_table.lookup(right).should be_nil
      right_table.lookup(left).should be_nil
    end

    it "rejects unissued owner ordinals but accepts issued duplicates" do
      table = SemanticTypeInternTable.new
      forged = SemanticTypeId.new(table, 0_u32)
      forged.canonical?.should be_false
      table.lookup(forged).should be_nil
      table.normalized_name(forged).should eq "Unknown"

      issued = table.primitive("Int32")
      duplicate = SemanticTypeId.new(table, issued.id)
      duplicate.should eq issued
      duplicate.canonical?.should be_true
      table.lookup(duplicate).should eq table.lookup(issued)
    end

    it "rejects foreign names and components at table admission" do
      local_names = NameInternTable.new
      local_table = SemanticTypeInternTable.new(local_names)
      foreign_table = SemanticTypeInternTable.new
      foreign_id = foreign_table.primitive("Int32")
      foreign_key = foreign_table.lookup(foreign_id).not_nil!

      expect_raises(ArgumentError) { local_table.intern(foreign_key) }

      local_name = local_names.intern("Array")
      expect_raises(ArgumentError) do
        local_table.intern(SemanticTypeKey.new(TypeKind::Array, local_name, [foreign_id]))
      end
      expect_raises(ArgumentError) do
        local_table.intern(SemanticTypeKey.new(TypeKind::Tuple, local_name, [] of SemanticTypeId))
      end
      expect_raises(ArgumentError) do
        local_table.intern(SemanticTypeKey.new(TypeKind::Array, local_name, [SemanticTypeId.new(7_u32)]))
      end
      forged_component = SemanticTypeId.new(local_table, 0_u32)
      expect_raises(ArgumentError) do
        local_table.intern(SemanticTypeKey.new(TypeKind::Array, local_name, [forged_component]))
      end
      local_table.lookup(foreign_id).should be_nil
      local_table.normalized_name(foreign_id).should eq "Unknown"
    end

    it "rejects UNKNOWN names for named shapes" do
      table = SemanticTypeInternTable.new
      expect_raises(ArgumentError) do
        table.intern(SemanticTypeKey.new(TypeKind::Primitive, NameId::UNKNOWN, [] of SemanticTypeId))
      end
      table.tuple([] of SemanticTypeId).should_not eq SemanticTypeId::UNKNOWN

      names = NameInternTable.new
      foreign_max = NameId.new(names, UInt32::MAX)
      foreign_max.unknown?.should be_false
      names.lookup(foreign_max).should be_nil
      table_with_names = SemanticTypeInternTable.new(names)
      expect_raises(ArgumentError) do
        table_with_names.intern(SemanticTypeKey.new(TypeKind::Tuple, foreign_max, [] of SemanticTypeId))
      end

      forged_type_max = SemanticTypeId.new(table, UInt32::MAX)
      forged_type_max.unknown?.should be_false
      table.lookup(forged_type_max).should be_nil
      expect_raises(ArgumentError) do
        table.intern(SemanticTypeKey.new(TypeKind::Tuple, NameId::UNKNOWN, [forged_type_max]))
      end
    end
  end

  # ── NameId ──

  describe "NameInternTable" do
    it "interns same spelling and resolves reverse" do
      table = NameInternTable.new
      first = table.intern("value")
      second = table.intern("value")
      first.should eq second
      table.lookup(first).should eq "value"
      table.size.should eq 1
    end

    it "assigns distinct numeric ids and preserves reverse order" do
      table = NameInternTable.new
      first = table.intern("left")
      second = table.intern("right")
      first.should_not eq second
      table.lookup(first).should eq "left"
      table.lookup(second).should eq "right"
    end

    it "owns the spelling independently of caller string mutation" do
      table = NameInternTable.new
      spelling = String.build { |io| io << "value" }
      id = table.intern(spelling)

      # Test-only mutation through the backing bytes. Production code treats
      # String as an input spelling and never retains caller-owned storage.
      spelling.to_unsafe[0] = 'X'.ord.to_u8

      table.intern("value").should eq id
      table.lookup(id).should eq "value"
    end

    it "returns nil for unknown names and out-of-bounds ids" do
      table = NameInternTable.new
      table.lookup("missing").should be_nil
      table.lookup(NameId::UNKNOWN).should be_nil
      table.intern("value")
      table.lookup(NameId.new(0_u32)).should be_nil
      table.lookup(NameId.new(123_u32)).should be_nil
    end

    it "keeps ordinals local to each compile-session table" do
      left_table = NameInternTable.new
      right_table = NameInternTable.new
      left = left_table.intern("value")
      right = right_table.intern("value")

      left.should_not eq right
      ids = {} of NameId => Int32
      ids[left] = 1
      ids[right] = 2
      ids.size.should eq 2
      left_table.lookup(right).should be_nil
      right_table.lookup(left).should be_nil
    end

    it "rejects unissued owner ordinals but accepts issued duplicates" do
      table = NameInternTable.new
      forged = NameId.new(table, 0_u32)
      forged.canonical?.should be_false
      table.lookup(forged).should be_nil

      issued = table.intern("value")
      duplicate = NameId.new(table, issued.id)
      duplicate.should eq issued
      duplicate.canonical?.should be_true
      table.lookup(duplicate).should eq "value"
    end

    it "does not expose the stored reverse spelling" do
      table = NameInternTable.new
      spelling = String.build { |io| io << "value" }
      id = table.intern(spelling)
      spelling.to_unsafe[0] = 'X'.ord.to_u8

      reverse = table.lookup(id).not_nil!
      reverse.to_unsafe[0] = 'Y'.ord.to_u8

      table.lookup(id).should eq "value"
      table.intern("value").should eq id
    end

    it "rejects reserved name id ordinal without filling the table" do
      table = NameInternTableOverflowProbe.new
      table.set_next_id_for_test(UInt32::MAX)
      expect_raises(Exception) { table.intern("overflow") }
      table.size.should eq 0
    end
  end

  # ── DefIdentity ──

  describe "DefIdentity" do
    it "equality by arena_id and expr_index" do
      a = DefIdentity.new(100_u64, 5)
      b = DefIdentity.new(100_u64, 5)
      c = DefIdentity.new(100_u64, 6)
      d = DefIdentity.new(200_u64, 5)
      (a == b).should be_true
      (a == c).should be_false
      (a == d).should be_false
    end

    it "hash stability" do
      a = DefIdentity.new(100_u64, 5)
      b = DefIdentity.new(100_u64, 5)
      a.hash.should eq b.hash
    end

    it "to_s includes hex arena and index" do
      d = DefIdentity.new(0xABC_u64, 42)
      d.to_s.should eq "Def@abc:42"
    end
  end

  # ── DefInstanceKey ──

  describe "DefInstanceKey" do
    it "equality with same components" do
      types = SemanticTypeInternTable.new
      def_id = DefIdentity.new(1_u64, 0)
      recv = types.primitive("Receiver")
      args = [types.primitive("Arg")]

      k1 = DefInstanceKey.new(def_identity: def_id, receiver_type: recv, arg_types: args)
      k2 = DefInstanceKey.new(def_identity: def_id, receiver_type: recv, arg_types: args)
      (k1 == k2).should be_true
      k1.hash.should eq k2.hash
    end

    it "different receiver = different key" do
      types = SemanticTypeInternTable.new
      def_id = DefIdentity.new(1_u64, 0)
      k1 = DefInstanceKey.new(def_identity: def_id, receiver_type: types.primitive("ReceiverA"))
      k2 = DefInstanceKey.new(def_identity: def_id, receiver_type: types.primitive("ReceiverB"))
      (k1 == k2).should be_false
    end

    it "different arg types = different key (overload separation)" do
      types = SemanticTypeInternTable.new
      def_id = DefIdentity.new(1_u64, 0)
      k1 = DefInstanceKey.new(def_identity: def_id, arg_types: [types.primitive("ArgA")])
      k2 = DefInstanceKey.new(def_identity: def_id, arg_types: [types.primitive("ArgB")])
      (k1 == k2).should be_false
    end

    it "different block_type = different key" do
      types = SemanticTypeInternTable.new
      def_id = DefIdentity.new(1_u64, 0)
      k1 = DefInstanceKey.new(def_identity: def_id, block_type: types.primitive("BlockA"))
      k2 = DefInstanceKey.new(def_identity: def_id, block_type: types.primitive("BlockB"))
      (k1 == k2).should be_false
    end

    it "defensive copy — mutating original array does not affect key" do
      types = SemanticTypeInternTable.new
      def_id = DefIdentity.new(1_u64, 0)
      args = [types.primitive("Arg")]
      key = DefInstanceKey.new(def_identity: def_id, arg_types: args)
      args << types.primitive("Extra")
      key.arg_types.size.should eq 1
    end

    it "works as hash key" do
      types = SemanticTypeInternTable.new
      def_id = DefIdentity.new(1_u64, 0)
      recv = types.primitive("Receiver")
      k1 = DefInstanceKey.new(def_identity: def_id, receiver_type: recv)
      k2 = DefInstanceKey.new(def_identity: def_id, receiver_type: recv)

      h = {} of DefInstanceKey => Int32
      h[k1] = 42
      h[k2].should eq 42
    end

    it "named arguments compare by canonical NameId order and value type" do
      table = NameInternTable.new
      left = table.intern("left")
      right = table.intern("right")
      types = SemanticTypeInternTable.new(table)
      def_id = DefIdentity.new(1_u64, 0)
      int = types.primitive("Int32")
      str = types.primitive("String")

      same = DefInstanceKey.new(
        def_identity: def_id,
        named_arg_types: [{left, int}, {right, str}]
      )
      equal = DefInstanceKey.new(
        def_identity: def_id,
        named_arg_types: [{left, int}, {right, str}]
      )
      reversed = DefInstanceKey.new(
        def_identity: def_id,
        named_arg_types: [{right, str}, {left, int}]
      )
      different_name = DefInstanceKey.new(
        def_identity: def_id,
        named_arg_types: [{right, int}, {left, str}]
      )

      same.should eq equal
      same.should eq reversed
      same.should_not eq different_name
      same.hash.should eq equal.hash
      same.hash.should eq reversed.hash
      same.to_s.should contain("named=[")
    end

    it "owns named argument arrays and keeps hash lookup stable" do
      table = NameInternTable.new
      name = table.intern("value")
      types = SemanticTypeInternTable.new(table)
      def_id = DefIdentity.new(1_u64, 0)
      named = [{name, types.primitive("Int32")}]
      key = DefInstanceKey.new(def_identity: def_id, named_arg_types: named)
      named << {name, types.primitive("String")}

      table_key = {} of DefInstanceKey => Int32
      table_key[key] = 42
      table_key[key].should eq 42
      key.named_arg_types.not_nil!.size.should eq 1
    end

    it "rejects duplicate named argument ids" do
      table = NameInternTable.new
      name = table.intern("value")
      types = SemanticTypeInternTable.new(table)
      expect_raises(ArgumentError) do
        DefInstanceKey.new(
          def_identity: DefIdentity.new(1_u64, 0),
          named_arg_types: [{name, types.primitive("Int32")}, {name, types.primitive("String")}]
        )
      end
    end

    it "does not expose mutable key arrays" do
      types = SemanticTypeInternTable.new
      def_id = DefIdentity.new(1_u64, 0)
      args = [types.primitive("Arg")]
      key = DefInstanceKey.new(def_identity: def_id, arg_types: args)
      key.arg_types.to_a << types.primitive("Extra")
      key.arg_types.size.should eq 1
    end

    it "does not alias keys from separate identity sessions" do
      left_names = NameInternTable.new
      right_names = NameInternTable.new
      left_types = SemanticTypeInternTable.new(left_names)
      right_types = SemanticTypeInternTable.new(right_names)
      left_name = left_names.intern("value")
      right_name = right_names.intern("value")
      left_type = left_types.primitive("Int32")
      right_type = right_types.primitive("Int32")
      def_id = DefIdentity.new(1_u64, 0)

      left = DefInstanceKey.new(
        def_identity: def_id,
        named_arg_types: [{left_name, left_type}]
      )
      right = DefInstanceKey.new(
        def_identity: def_id,
        named_arg_types: [{right_name, right_type}]
      )

      left.should_not eq right
      keys = {} of DefInstanceKey => Int32
      keys[left] = 1
      keys[right] = 2
      keys.size.should eq 2
    end

    it "rejects raw, UNKNOWN, and mixed-scope identity components" do
      left_names = NameInternTable.new
      right_names = NameInternTable.new
      left_types = SemanticTypeInternTable.new(left_names)
      right_types = SemanticTypeInternTable.new(right_names)
      left_name = left_names.intern("value")
      left_other_name = left_names.intern("other")
      right_name = right_names.intern("value")
      left_type = left_types.primitive("Int32")
      right_type = right_types.primitive("Int32")
      def_id = DefIdentity.new(1_u64, 0)

      forged_name = NameId.new(left_names, 99_u32)
      forged_type = SemanticTypeId.new(left_types, 1_u32)
      expect_raises(ArgumentError) do
        DefInstanceKey.new(def_identity: def_id, named_arg_types: [{forged_name, left_type}])
      end
      expect_raises(ArgumentError) do
        DefInstanceKey.new(def_identity: def_id, arg_types: [forged_type])
      end
      expect_raises(ArgumentError) do
        DefInstanceKey.new(def_identity: def_id, arg_types: [SemanticTypeId.new(0_u32)])
      end
      expect_raises(ArgumentError) do
        DefInstanceKey.new(def_identity: def_id, named_arg_types: [{NameId::UNKNOWN, left_type}])
      end
      expect_raises(ArgumentError) do
        DefInstanceKey.new(def_identity: def_id, named_arg_types: [{left_name, left_type}, {right_name, left_type}])
      end
      expect_raises(ArgumentError) do
        DefInstanceKey.new(def_identity: def_id, named_arg_types: [{right_name, left_type}])
      end
      expect_raises(ArgumentError) do
        DefInstanceKey.new(def_identity: def_id, named_arg_types: [{left_name, left_type}, {left_other_name, right_type}])
      end
      expect_raises(ArgumentError) do
        DefInstanceKey.new(def_identity: def_id, receiver_type: left_type, arg_types: [right_type])
      end
      expect_raises(ArgumentError) do
        DefInstanceKey.new(def_identity: def_id, receiver_type: left_type, named_arg_types: [{left_name, right_type}])
      end
    end
  end

  # ── Identity dry-run removal guard ──

  describe "Identity dry-run removal" do
    it "removes the proxy tracker while preserving canonical phase0 metrics" do
      root = File.expand_path("../..", __DIR__)
      ast_to_hir = File.read(File.join(root, "src/compiler/hir/ast_to_hir.cr"))
      cli = File.read(File.join(root, "src/compiler/cli.cr"))
      name_identity = File.read(File.join(root, "src/compiler/semantic/identity/name_id.cr"))
      type_identity = File.read(File.join(root, "src/compiler/semantic/identity/semantic_type_id.cr"))
      production_source = Dir.glob(File.join(root, "src", "**", "*.cr")).map { |path| File.read(path) }.join("\n")

      File.exists?(File.join(root, "src/compiler/semantic/identity/dry_run_tracker.cr")).should be_false
      production_source.should_not contain("IdentityDryRunTracker")
      production_source.should_not contain("ADAMAS_IDENTITY_DRY_RUN")
      production_source.should_not contain("identity/dry_run_tracker")
      production_source.should_not contain("identity_tracker")
      ast_to_hir.should contain("ADAMAS_PHASE0_METRICS")
      ast_to_hir.should contain("canonical_def_identity_for_body_infer")
      cli.should contain("ADAMAS_PHASE0_METRICS")
      name_identity.should_not contain("IdentityScope")
      type_identity.should_not contain("IdentityScope")
      name_identity.should contain("@owner : NameInternTable?")
      type_identity.should contain("@owner : SemanticTypeInternTable?")
      name_identity.should_not contain("getter owner")
      type_identity.should_not contain("getter owner")
      NameId.new(nil, 0_u32).canonical?.should be_false
      SemanticTypeId.new(nil, 0_u32).canonical?.should be_false
    end
  end
end
