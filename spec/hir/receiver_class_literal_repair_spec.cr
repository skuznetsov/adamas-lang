require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_repair_receiver_bound_call_targets : Nil
    repair_receiver_bound_call_targets
  end
end

private def parse_receiver_repair_source(code : String) : {Adamas::HIR::AstToHir, Array(Adamas::HIR::Function)}
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  defs = [] of Adamas::Compiler::Frontend::DefNode
  result.roots.each do |root_id|
    case node = result.arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      modules << node
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::DefNode
      defs << node
    end
  end

  modules.each { |node| converter.register_module(node) }
  classes.each { |node| converter.register_class(node) }
  defs.each { |node| converter.register_function(node) }
  modules.each { |node| converter.lower_module(node) }
  classes.each { |node| converter.lower_class(node) }
  defs.each { |node| converter.lower_def(node) }

  {converter, converter.module.functions}
end

describe "receiver-bound class-literal repair" do
  it "rekeys a receiverless class-method arity target from concrete callsite types" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      module TinyGlob
        def self.compile(pattern : String) : String
          single_compile(pattern)
        end

        private def self.single_compile(glob)
          glob
        end
      end
    CRYSTAL

    caller = functions.find { |candidate| candidate.name.starts_with?("TinyGlob.compile$") }
    caller.should_not be_nil
    call = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("single_compile") }
    call.should_not be_nil
    original = call.not_nil!
    original.args.size.should eq(1)

    # Model the s2 stale target: the callsite carries String but retains the
    # shared arity symbol that was materialized with an untyped/Void parameter.
    # Class-method lowering normally leaves a synthetic type-literal receiver;
    # erase it here so this seam is specifically the receiverless dotted form.
    call_block = caller.not_nil!.blocks.find { |candidate| candidate.instructions.includes?(original) }
    call_block.should_not be_nil
    call_index = call_block.not_nil!.instructions.index(original).not_nil!
    stale = Adamas::HIR::Call.without_receiver(
      original.id,
      original.type,
      "TinyGlob.single_compile$arity1",
      original.args,
    )
    call_block.not_nil!.instructions[call_index] = stale
    original = stale
    original.has_receiver?.should be_false

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.id == original.id }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.method_name.should contain("TinyGlob.single_compile$String")
    repaired_call.not_nil!.method_name.should_not contain("$arity")
    typed = functions.find { |candidate| candidate.name == "TinyGlob.single_compile$String" }
    typed.should_not be_nil
    typed.not_nil!.params.last.type.should eq(Adamas::HIR::TypeRef::STRING)
  end

  it "fails closed for unknown arity targets while separating concrete callsite types" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      module TinyGlob
        def self.string_call(pattern : String) : String
          single_compile(pattern)
        end

        def self.int_call(value : Int32) : Int32
          single_compile(value)
        end

        def self.unknown_call(pattern : String) : String
          single_compile(pattern)
        end

        private def self.single_compile(glob)
          glob
        end
      end
    CRYSTAL

    stale_calls = {
      "string_call" => "String",
      "int_call" => "Int32",
    }
    stale_calls.each do |caller_name, expected_type|
      caller = functions.find { |candidate| candidate.name.starts_with?("TinyGlob.#{caller_name}$") }
      caller.should_not be_nil
      call = caller.not_nil!.blocks.flat_map(&.instructions)
        .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
        .find { |instruction| instruction.method_name.includes?("single_compile") }
      call.should_not be_nil
      original = call.not_nil!
      call_block = caller.not_nil!.blocks.find { |candidate| candidate.instructions.includes?(original) }
      call_block.should_not be_nil
      call_index = call_block.not_nil!.instructions.index(original).not_nil!
      call_block.not_nil!.instructions[call_index] = Adamas::HIR::Call.without_receiver(
        original.id,
        original.type,
        "TinyGlob.single_compile$arity1",
        original.args,
      )
    end

    unknown_caller = functions.find { |candidate| candidate.name.starts_with?("TinyGlob.unknown_call$") }
    unknown_caller.should_not be_nil
    unknown = unknown_caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("single_compile") }
    unknown.should_not be_nil
    unknown_original = unknown.not_nil!
    unknown_block = unknown_caller.not_nil!.blocks.find { |candidate| candidate.instructions.includes?(unknown_original) }
    unknown_block.should_not be_nil
    unknown_index = unknown_block.not_nil!.instructions.index(unknown_original).not_nil!
    unknown_block.not_nil!.instructions[unknown_index] = Adamas::HIR::Call.without_receiver(
      unknown_original.id,
      unknown_original.type,
      "TinyGlob.missing$arity1",
      unknown_original.args,
    )

    converter.__test_repair_receiver_bound_call_targets

    string_call = functions.find { |candidate| candidate.name.starts_with?("TinyGlob.string_call$") }.not_nil!
    # Locate by the rewritten symbol rather than relying on a particular local id.
    string_call.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .any? { |instruction| instruction.method_name == "TinyGlob.single_compile$String" }
      .should be_true

    int_call = functions.find { |candidate| candidate.name.starts_with?("TinyGlob.int_call$") }.not_nil!
    int_call.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .any? { |instruction| instruction.method_name == "TinyGlob.single_compile$Int32" }
      .should be_true

    unknown_caller.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .any? { |instruction| instruction.method_name == "TinyGlob.missing$arity1" }
      .should be_true
  end

  it "keeps backend_class.remove_impl on the class-method separator" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class FileDescriptor
      end

      class Socket
      end

      abstract class Polling
        def self.remove_impl(file_descriptor : FileDescriptor) : Nil
          nil
        end

        def self.remove_impl(socket : Socket) : Nil
          nil
        end
      end

      class EventLoop
        def self.backend_class
          Polling
        end

        def self.remove(file_descriptor : FileDescriptor) : Nil
          backend_class.remove_impl(file_descriptor)
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.starts_with?("EventLoop.remove$") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("remove_impl") }
    call.should_not be_nil
    backend_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("backend_class") }
    backend_call.should_not be_nil
    backend_block = function.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(backend_call.not_nil!)
    end
    backend_block.should_not be_nil
    backend_index = backend_block.not_nil!.instructions.index(backend_call.not_nil!).not_nil!
    backend = backend_call.not_nil!
    backend_block.not_nil!.instructions[backend_index] = Adamas::HIR::Call.without_receiver(
      backend.id, Adamas::HIR::TypeRef::STRING, backend.method_name, backend.args
    )
    # Model the s2 HIR stale-owner shape observed before receiver repair.
    call.not_nil!.method_name = "String#remove_impl$FileDescriptor"

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("remove_impl") }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_false
    repaired_call.not_nil!.method_name.should start_with("Polling.remove_impl")
  end

  it "keeps a real instance producer receiver-bound" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class Service
        def self.make : Service
          Service.new
        end

        def ping : Nil
          nil
        end
      end

      class Caller
        def self.use : Nil
          Service.make.ping
        end
      end
    CRYSTAL

    converter.__test_repair_receiver_bound_call_targets

    function = functions.find { |candidate| candidate.name.starts_with?("Caller.use$") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("ping") }
    call.should_not be_nil
    call.not_nil!.has_receiver?.should be_true
    call.not_nil!.method_name.should contain("Service#ping")
  end

  it "repairs stale self calls inside a class method without dropping real args" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      module Probe
        def self.enabled?(key : String) : Bool
          false
        end

        def self.trace(key : String) : Bool
          enabled?(key)
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.includes?("Probe.trace") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    call.should_not be_nil
    call.not_nil!.method_name = "Probe#enabled?$String"

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_false
    repaired_call.not_nil!.args.size.should eq(1)
    repaired_call.not_nil!.method_name.should start_with("Probe.enabled?")
  end

  it "does not drop an explicit same-type instance argument in a class method" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class Probe
        def self.enabled?(key : String) : Bool
          false
        end

        def enabled?(key : String) : Bool
          false
        end

        def self.trace(probe : Probe, key : String) : Bool
          probe.enabled?(key)
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.includes?("Probe.trace") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    call.should_not be_nil
    call.not_nil!.method_name = "Probe#enabled?$String"

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_true
    repaired_call.not_nil!.args.size.should eq(1)
  end

  it "repairs namespaced module class-self calls on the exact dot target" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      module Adamas
        module LayoutProbe
          def self.enabled?(key : String) : Bool
            false
          end

          def self.trace(key : String) : Bool
            enabled?(key)
          end
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.includes?("Adamas::LayoutProbe.trace") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    call.should_not be_nil
    call.not_nil!.method_name = "Adamas::LayoutProbe#enabled?$String"

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_false
    repaired_call.not_nil!.args.size.should eq(1)
    repaired_call.not_nil!.method_name.should start_with("Adamas::LayoutProbe.enabled?")
  end

  it "repairs a namespaced zero-argument class-self call without a suffix" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      module Adamas
        module LayoutProbe
          def self.enabled? : Bool
            false
          end

          def self.trace : Bool
            enabled?
          end
        end
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.includes?("Adamas::LayoutProbe.trace") }
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    call.should_not be_nil
    block = function.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(call.not_nil!)
    end
    block.should_not be_nil
    call_index = block.not_nil!.instructions.index(call.not_nil!).not_nil!
    original = call.not_nil!
    block.not_nil!.instructions[call_index] = Adamas::HIR::Call.with_receiver_virtual(
      original.id, original.type, original.receiver_value, "Adamas::LayoutProbe#enabled?", original.args, true
    )

    converter.__test_repair_receiver_bound_call_targets

    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("enabled?") }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_false
    repaired_call.not_nil!.method_name.should eq("Adamas::LayoutProbe.enabled?")
  end

  it "keeps a same-name class-method block forward on the class separator" do
    converter, functions = parse_receiver_repair_source(<<-CRYSTAL)
      class GlobForwarder
        def self.glob(values : Array(String), match : Int32 = 0, follow_symlinks : Bool = false) : Array(String)
          result = [] of String
          glob(values, match: match, follow_symlinks: follow_symlinks) { |value| result << value }
          result
        end

        def self.glob(values : Array(String), match : Int32 = 0, follow_symlinks : Bool = false, &block : String ->) : Nil
          nil
        end
      end
    CRYSTAL

    function = functions.find do |candidate|
      candidate.name.starts_with?("GlobForwarder.glob$") && !candidate.name.includes?("_block")
    end
    function.should_not be_nil
    call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("glob") && instruction.has_block? }
    call.should_not be_nil
    original = call.not_nil!
    block = function.not_nil!.blocks.find do |candidate|
      candidate.instructions.includes?(original)
    end
    block.should_not be_nil
    call_index = block.not_nil!.instructions.index(original).not_nil!
    block.not_nil!.instructions[call_index] = Adamas::HIR::Call.without_receiver_block(
      original.id,
      original.type,
      "GlobForwarder.glob",
      original.args,
      original.block_value,
      false
    )

    converter.__test_repair_receiver_bound_call_targets
    repaired_call = function.not_nil!.blocks.flat_map(&.instructions)
      .compact_map { |instruction| instruction.as?(Adamas::HIR::Call) }
      .find { |instruction| instruction.method_name.includes?("glob") && instruction.has_block? }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.has_receiver?.should be_false
    repaired_call.not_nil!.method_name.should contain("GlobForwarder.glob")
    repaired_call.not_nil!.method_name.should contain("_block")
  end

end
