class SelectedInitializerTrailingDefaults
  @@default_calls = 0

  def self.next_span : Int32
    @@default_calls += 1
    17
  end

  def self.default_calls : Int32
    @@default_calls
  end

  getter marker : Int32
  getter flags : Int32

  def initialize(
    name : String?,
    external_name : String?,
    type_annotation : String,
    default_value : Int32? = nil,
    span : Int32 = 0,
    name_span : Int32? = SelectedInitializerTrailingDefaults.next_span,
    external_name_span : Int32? = nil,
    type_span : Int32? = nil,
    default_span : Int32? = nil,
    is_splat : Bool = false,
    is_double_splat : Bool = false,
    is_block : Bool = false,
    is_instance_var : Bool = false,
  )
    @marker = span + (name_span || 0) + type_annotation.bytesize
    @flags = (is_splat ? 1 : 0) + (is_double_splat ? 2 : 0) + (is_block ? 4 : 0) + (is_instance_var ? 8 : 0)
  end
end

first = SelectedInitializerTrailingDefaults.new(nil, nil, "T", nil, 5, nil, nil, nil, nil, true, false, true, false)
named_gap = SelectedInitializerTrailingDefaults.new(nil, nil, type_annotation: "N", span: 7)
name : String? = nil
nil_arm = SelectedInitializerTrailingDefaults.new(name, nil, "Q")
name = "x"
string_arm = SelectedInitializerTrailingDefaults.new(name, nil, "R")

puts first.marker
puts first.flags
puts named_gap.marker
puts named_gap.flags
puts nil_arm.marker
puts nil_arm.flags
puts string_arm.marker
puts string_arm.flags
puts SelectedInitializerTrailingDefaults.default_calls
