module Adamas::Compiler::PredefinedSourceTypes
  # Source-visible nominal types installed by Crystal's Program#initialize
  # before it reads source. This inventory excludes non-namespace sentinels
  # such as Void and NoReturn, built-in annotations, and predefined constants.
  record Metadata,
    is_module : Bool,
    is_struct : Bool,
    is_abstract : Bool,
    superclass_name : String?,
    type_parameters : Array(String)?,
    non_generic_class : Bool

  def self.metadata(name : String) : Metadata?
    case name
    when "Object"
      class_type(nil, is_abstract: true, non_generic: true)
    when "Reference"
      class_type("Object", non_generic: true)
    when "Value", "Struct", "Number", "Int", "Float", "Enum"
      superclass = case name
                   when "Value" then "Object"
                   when "Struct" then "Value"
                   when "Number" then "Value"
                   when "Int" then "Number"
                   when "Float" then "Number"
                   else             "Value"
                   end
      class_type(superclass, is_struct: true, is_abstract: true, non_generic: true)
    when "Nil", "Bool", "Char", "Symbol"
      class_type("Value", is_struct: true)
    when "Int8", "UInt8", "Int16", "UInt16", "Int32", "UInt32", "Int64", "UInt64", "Int128", "UInt128"
      class_type("Int", is_struct: true)
    when "Float32", "Float64"
      class_type("Float", is_struct: true)
    when "Pointer"
      class_type("Value", is_struct: true, type_parameters: ["T"] of String)
    when "Tuple", "NamedTuple"
      class_type("Value", is_struct: true, type_parameters: ["T"] of String)
    when "StaticArray"
      class_type("Value", is_struct: true, type_parameters: ["T", "N"] of String)
    when "String", "Regex", "Exception"
      class_type("Reference", non_generic: true)
    when "Class"
      class_type("Value")
    when "Enumerable", "Indexable"
      module_type(["T"] of String)
    when "Array"
      class_type("Reference", type_parameters: ["T"] of String)
    when "Hash"
      class_type("Reference", type_parameters: ["K", "V"] of String)
    when "Range"
      class_type("Struct", is_struct: true, type_parameters: ["B", "E"] of String)
    when "Slice"
      class_type("Struct", is_struct: true, type_parameters: ["T"] of String)
    when "Proc"
      class_type("Value", is_struct: true, type_parameters: ["T", "R"] of String)
    when "Union"
      class_type("Value", is_struct: true, type_parameters: ["T"] of String)
    when "Crystal", "GC"
      module_type
    else
      nil
    end
  end

  def self.namespace?(name : String) : Bool
    !metadata(name).nil?
  end

  # Keep this exact subset aligned with the existing HIR contract: these are
  # Program#initialize entries created as NonGenericClassType values.
  def self.non_generic_class_metadata(name : String) : Tuple(Bool, Bool)?
    entry = metadata(name)
    return nil unless entry && entry.non_generic_class

    {entry.is_struct, entry.is_abstract}
  end

  private def self.class_type(
    superclass_name : String?,
    *,
    is_struct : Bool = false,
    is_abstract : Bool = false,
    type_parameters : Array(String)? = nil,
    non_generic : Bool = false,
  ) : Metadata
    Metadata.new(false, is_struct, is_abstract, superclass_name, type_parameters, non_generic)
  end

  private def self.module_type(type_parameters : Array(String)? = nil) : Metadata
    Metadata.new(true, false, false, nil, type_parameters, false)
  end
end
