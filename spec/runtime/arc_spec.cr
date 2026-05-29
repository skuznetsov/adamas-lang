require "../spec_helper"
require "../../src/runtime/runtime"

describe Adamas::Runtime do
  describe "ARC constants" do
    it "has correct header size" do
      Adamas::Runtime::ARC_HEADER_SIZE.should eq(16)
    end

    it "has correct offsets" do
      Adamas::Runtime::RC_OFFSET.should eq(-16)
      Adamas::Runtime::TYPE_ID_OFFSET.should eq(-8)
      Adamas::Runtime::FLAGS_OFFSET.should eq(-4)
    end
  end

  describe ".arc_alloc" do
    it "allocates object with header" do
      ptr = Adamas::Runtime.arc_alloc(32_u64, 100_u32)
      ptr.null?.should be_false

      # Check initial ref count is 1
      Adamas::Runtime.rc_get(ptr).should eq(1)

      # Check type_id
      Adamas::Runtime.type_id_ptr(ptr).value.should eq(100)

      # Clean up - decrement should free
      Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
    end

    it "initializes flags to zero" do
      ptr = Adamas::Runtime.arc_alloc(16_u64, 50_u32)
      Adamas::Runtime.flags_ptr(ptr).value.should eq(0)
      Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
    end
  end

  describe ".rc_inc" do
    it "increments reference count" do
      ptr = Adamas::Runtime.arc_alloc(32_u64, 100_u32)

      Adamas::Runtime.rc_get(ptr).should eq(1)
      Adamas::Runtime.rc_inc(ptr)
      Adamas::Runtime.rc_get(ptr).should eq(2)
      Adamas::Runtime.rc_inc(ptr)
      Adamas::Runtime.rc_get(ptr).should eq(3)

      # Clean up
      Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
      Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
      Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
    end

    it "handles null pointer" do
      result = Adamas::Runtime.rc_inc(Pointer(Void).null)
      result.should eq(Adamas::Runtime::RC_IMMORTAL)
    end
  end

  describe ".rc_dec" do
    it "decrements reference count" do
      ptr = Adamas::Runtime.arc_alloc(32_u64, 100_u32)
      Adamas::Runtime.rc_inc(ptr)  # rc = 2
      Adamas::Runtime.rc_inc(ptr)  # rc = 3

      Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)  # rc = 2
      Adamas::Runtime.rc_get(ptr).should eq(2)

      Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)  # rc = 1
      Adamas::Runtime.rc_get(ptr).should eq(1)

      # Final decrement should free
      freed = Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
      freed.should be_true
    end

    it "handles null pointer" do
      freed = Adamas::Runtime.rc_dec(Pointer(Void).null, Pointer(Void).null)
      freed.should be_false
    end

    it "returns true when object is freed" do
      ptr = Adamas::Runtime.arc_alloc(32_u64, 100_u32)
      freed = Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
      freed.should be_true
    end

    it "returns false when count > 0" do
      ptr = Adamas::Runtime.arc_alloc(32_u64, 100_u32)
      Adamas::Runtime.rc_inc(ptr)  # rc = 2

      freed = Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)  # rc = 1
      freed.should be_false

      Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)  # Cleanup
    end
  end

  describe ".rc_is_immortal?" do
    it "returns false for normal objects" do
      ptr = Adamas::Runtime.arc_alloc(32_u64, 100_u32)
      Adamas::Runtime.rc_is_immortal?(ptr).should be_false
      Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
    end
  end
end

describe "__adamas_rc_inc" do
  it "is callable" do
    ptr = Adamas::Runtime.arc_alloc(32_u64, 100_u32)
    __adamas_rc_inc(ptr)
    Adamas::Runtime.rc_get(ptr).should eq(2)
    Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
    Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
  end
end

describe "__adamas_rc_dec" do
  it "is callable" do
    ptr = Adamas::Runtime.arc_alloc(32_u64, 100_u32)
    Adamas::Runtime.rc_inc(ptr)
    __adamas_rc_dec(ptr, Pointer(Void).null)
    Adamas::Runtime.rc_get(ptr).should eq(1)
    Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
  end
end

describe "__adamas_arc_alloc" do
  it "is callable" do
    ptr = __adamas_arc_alloc(64_u64, 200_u32)
    ptr.null?.should be_false
    __adamas_rc_get(ptr).should eq(1)
    __adamas_rc_dec(ptr, Pointer(Void).null)
  end
end

describe "__adamas_rc_get" do
  it "returns reference count" do
    ptr = Adamas::Runtime.arc_alloc(32_u64, 100_u32)
    __adamas_rc_get(ptr).should eq(1)
    Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
  end
end

describe "__adamas_rc_is_valid" do
  it "returns true for valid objects" do
    ptr = Adamas::Runtime.arc_alloc(32_u64, 100_u32)
    __adamas_rc_is_valid(ptr).should be_true
    Adamas::Runtime.rc_dec(ptr, Pointer(Void).null)
  end

  it "returns false for null" do
    __adamas_rc_is_valid(Pointer(Void).null).should be_false
  end
end
