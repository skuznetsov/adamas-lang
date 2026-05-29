require "spec"
require "../../src/compiler/semantic/identity/semantic_type_id"
require "../../src/compiler/semantic/identity/def_identity"
require "../../src/compiler/semantic/identity/def_instance_key"
require "../../src/compiler/semantic/identity/dry_run_tracker"
require "../../src/compiler/semantic/identity/def_instance_key"

module IdentitySpec
  include Adamas::Compiler::Semantic

  # ── SemanticTypeId ──

  describe "SemanticTypeId" do
    it "equality by id" do
      a = SemanticTypeId.new(42_u32)
      b = SemanticTypeId.new(42_u32)
      c = SemanticTypeId.new(99_u32)
      (a == b).should be_true
      (a == c).should be_false
    end

    it "hash stability — same id always same hash" do
      a = SemanticTypeId.new(7_u32)
      b = SemanticTypeId.new(7_u32)
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
      key.not_nil!.name.should eq "Float64"
      key.not_nil!.kind.should eq TypeKind::Primitive
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
      def_id = DefIdentity.new(1_u64, 0)
      recv = SemanticTypeId.new(10_u32)
      args = [SemanticTypeId.new(20_u32)]

      k1 = DefInstanceKey.new(def_identity: def_id, receiver_type: recv, arg_types: args)
      k2 = DefInstanceKey.new(def_identity: def_id, receiver_type: recv, arg_types: args)
      (k1 == k2).should be_true
      k1.hash.should eq k2.hash
    end

    it "different receiver = different key" do
      def_id = DefIdentity.new(1_u64, 0)
      k1 = DefInstanceKey.new(def_identity: def_id, receiver_type: SemanticTypeId.new(10_u32))
      k2 = DefInstanceKey.new(def_identity: def_id, receiver_type: SemanticTypeId.new(11_u32))
      (k1 == k2).should be_false
    end

    it "different arg types = different key (overload separation)" do
      def_id = DefIdentity.new(1_u64, 0)
      k1 = DefInstanceKey.new(def_identity: def_id, arg_types: [SemanticTypeId.new(20_u32)])
      k2 = DefInstanceKey.new(def_identity: def_id, arg_types: [SemanticTypeId.new(21_u32)])
      (k1 == k2).should be_false
    end

    it "different block_type = different key" do
      def_id = DefIdentity.new(1_u64, 0)
      k1 = DefInstanceKey.new(def_identity: def_id, block_type: SemanticTypeId.new(30_u32))
      k2 = DefInstanceKey.new(def_identity: def_id, block_type: SemanticTypeId.new(31_u32))
      (k1 == k2).should be_false
    end

    it "defensive copy — mutating original array does not affect key" do
      def_id = DefIdentity.new(1_u64, 0)
      args = [SemanticTypeId.new(20_u32)]
      key = DefInstanceKey.new(def_identity: def_id, arg_types: args)
      args << SemanticTypeId.new(99_u32)
      key.arg_types.size.should eq 1
    end

    it "works as hash key" do
      def_id = DefIdentity.new(1_u64, 0)
      recv = SemanticTypeId.new(10_u32)
      k1 = DefInstanceKey.new(def_identity: def_id, receiver_type: recv)
      k2 = DefInstanceKey.new(def_identity: def_id, receiver_type: recv)

      h = {} of DefInstanceKey => Int32
      h[k1] = 42
      h[k2].should eq 42
    end
  end

  # ── DryRunDefKey ──

  describe "DryRunDefKey" do
    it "equality by arena_id and node_object_id" do
      a = DryRunDefKey.new(100_u64, 200_u64)
      b = DryRunDefKey.new(100_u64, 200_u64)
      c = DryRunDefKey.new(100_u64, 300_u64)
      (a == b).should be_true
      (a == c).should be_false
    end

    it "hash stability" do
      a = DryRunDefKey.new(100_u64, 200_u64)
      b = DryRunDefKey.new(100_u64, 200_u64)
      a.hash.should eq b.hash
    end

    it "uses full UInt64 — no truncation" do
      large = DryRunDefKey.new(0xFFFF_FFFF_FFFF_u64, 0xAAAA_BBBB_CCCC_u64)
      large.arena_id.should eq 0xFFFF_FFFF_FFFF_u64
      large.node_object_id.should eq 0xAAAA_BBBB_CCCC_u64
    end
  end

  # ── DryRunInstanceKey ──

  describe "DryRunInstanceKey" do
    it "equality with same components" do
      dk = DryRunDefKey.new(1_u64, 2_u64)
      recv = SemanticTypeId.new(10_u32)
      k1 = DryRunInstanceKey.new(def_key: dk, receiver_type: recv)
      k2 = DryRunInstanceKey.new(def_key: dk, receiver_type: recv)
      (k1 == k2).should be_true
      k1.hash.should eq k2.hash
    end

    it "different arg types = different key" do
      dk = DryRunDefKey.new(1_u64, 2_u64)
      k1 = DryRunInstanceKey.new(def_key: dk, arg_types: [SemanticTypeId.new(20_u32)])
      k2 = DryRunInstanceKey.new(def_key: dk, arg_types: [SemanticTypeId.new(21_u32)])
      (k1 == k2).should be_false
    end

    it "defensive copy — mutating original array does not affect key" do
      dk = DryRunDefKey.new(1_u64, 2_u64)
      args = [SemanticTypeId.new(20_u32)]
      key = DryRunInstanceKey.new(def_key: dk, arg_types: args)
      args << SemanticTypeId.new(99_u32)
      key.arg_types.size.should eq 1
    end
  end

  # ── DryRunTracker ──

  describe "IdentityDryRunTracker" do
    it "canonical: first encounter is miss, second is hit" do
      tracker = IdentityDryRunTracker.new
      def_id = DefIdentity.new(1_u64, 10)
      key = DefInstanceKey.new(def_identity: def_id)
      tracker.record_canonical(key).should be_false
      tracker.record_canonical(key).should be_true
      tracker.total_lookups.should eq 2
      tracker.canonical_lookups.should eq 2
      tracker.surrogate_lookups.should eq 0
      tracker.cache_hits.should eq 1
      tracker.cache_misses.should eq 1
    end

    it "surrogate: first encounter is miss, second is hit" do
      tracker = IdentityDryRunTracker.new
      dk = DryRunDefKey.new(1_u64, 100_u64)
      key = DryRunInstanceKey.new(def_key: dk)
      tracker.record_surrogate(key).should be_false
      tracker.record_surrogate(key).should be_true
      tracker.total_lookups.should eq 2
      tracker.surrogate_lookups.should eq 2
      tracker.canonical_lookups.should eq 0
      tracker.cache_hits.should eq 1
    end

    it "canonical and surrogate are separate namespaces" do
      tracker = IdentityDryRunTracker.new
      # Same "identity" values but different key types should not collide
      ckey = DefInstanceKey.new(def_identity: DefIdentity.new(1_u64, 10))
      skey = DryRunInstanceKey.new(def_key: DryRunDefKey.new(1_u64, 10_u64))
      tracker.record_canonical(ckey).should be_false
      tracker.record_surrogate(skey).should be_false
      tracker.cache_hits.should eq 0
      tracker.cache_misses.should eq 2
    end

    it "different canonical keys are separate misses" do
      tracker = IdentityDryRunTracker.new
      k1 = DefInstanceKey.new(def_identity: DefIdentity.new(1_u64, 0))
      k2 = DefInstanceKey.new(def_identity: DefIdentity.new(2_u64, 0))
      tracker.record_canonical(k1).should be_false
      tracker.record_canonical(k2).should be_false
      tracker.cache_hits.should eq 0
      tracker.cache_misses.should eq 2
    end

    it "intern_type_name returns same id for same name" do
      tracker = IdentityDryRunTracker.new
      a = tracker.intern_type_name("Int32")
      b = tracker.intern_type_name("Int32")
      (a == b).should be_true
    end

    it "intern_type_name maps Nil and Void to same id" do
      tracker = IdentityDryRunTracker.new
      a = tracker.intern_type_name("Nil")
      b = tracker.intern_type_name("Void")
      (a == b).should be_true
    end

    it "dump shows canonical vs surrogate split" do
      tracker = IdentityDryRunTracker.new
      ckey = DefInstanceKey.new(def_identity: DefIdentity.new(1_u64, 0))
      skey = DryRunInstanceKey.new(def_key: DryRunDefKey.new(2_u64, 200_u64))
      tracker.record_canonical(ckey)
      tracker.record_canonical(ckey)
      tracker.record_surrogate(skey)
      io = IO::Memory.new
      tracker.dump(io)
      output = io.to_s
      output.should contain("[IDENTITY_DRY_RUN]")
      output.should contain("lookups=3")
      output.should contain("canonical=2")
      output.should contain("surrogate=1")
    end
  end
end
