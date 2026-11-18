# EXPECT: four parameter shapes ok
# Runtime unions in two independent initializer slots must retain the exact
# selected source initializer while its trailing defaults are expanded.
require "../src/compiler/frontend/ast"

def validate(first : Bool, second : Bool)
  name = first ? "field".to_slice : nil
  name_span = second ? Adamas::Compiler::Frontend::Span.zero : nil
  parameter = Adamas::Compiler::Frontend::Parameter.new(
    name, nil, "T".to_slice, nil, Adamas::Compiler::Frontend::Span.zero,
    name_span, nil, nil, nil,
  )
  LibC.exit(97) if parameter.name.nil? == first || parameter.name_span.nil? == second
  LibC.exit(98) if parameter.is_splat || parameter.is_double_splat || parameter.is_block || parameter.is_instance_var
end

validate(false, false)
validate(true, false)
validate(false, true)
validate(true, true)
puts "four parameter shapes ok"
