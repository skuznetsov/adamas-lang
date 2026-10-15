require "../spec_helper"
require "../semantic_cli_helpers"
require "../../src/compiler/cli"

include SemanticCliSpecHelpers

private def named_block_forwarding_hir(source : String) : String
  with_temp_shadow_project({"main.cr" => source}) do |dir|
    target = File.join(dir, "main")
    errors = IO::Memory.new
    status = Adamas::Compiler::CLI.new([
      File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir",
      "--no-link", "--no-ast-cache", "--no-llvm-cache", "-o", target,
    ]).run(out_io: IO::Memory.new, err_io: errors)

    status.should eq(0), errors.to_s
    File.read("#{target}.hir")
  end
end

private def named_block_forwarding_hir_function(hir : String, function_name : String) : String
  marker = "func @#{function_name}("
  start = hir.index(marker)
  start.should_not be_nil
  body_start = start.not_nil!
  next_function = hir.index("\nfunc @", body_start + marker.bytesize) || hir.bytesize
  hir.byte_slice(body_start, next_function - body_start)
end

describe "named forwarded block call shape" do
  it "keeps all named values in overload arity while preserving raw positional count" do
    hir = named_block_forwarding_hir(<<-CRYSTAL)
      module NamedBlockForwardingContract
        module Scheduler
          def spawn(*, name : String? = nil, &block : -> Int32) : Int32
            block.call
          end

          abstract def spawn(*, name : String? = nil, same_thread : Bool, &block : -> Int32) : Int32
        end

        module Parallel
          class Scheduler
            include NamedBlockForwardingContract::Scheduler

            def spawn(*, name : String? = nil, same_thread : Bool, &block : -> Int32) : Int32
              return 99 if same_thread
              self.spawn(name: name, &block)
            end
          end
        end
      end

      scheduler = NamedBlockForwardingContract::Parallel::Scheduler.new
      scheduler.spawn(name: "outer", same_thread: false) { 41 }
      CRYSTAL

    # The concrete two-label call stays on its source method. Its false branch
    # forwards the named block to the inherited one-label implementation, whose
    # body is lowered as a Proc call in this HIR path.
    concrete_body = named_block_forwarding_hir_function(
      hir,
      "NamedBlockForwardingContract::Parallel::Scheduler#spawn$Nil | String_Bool_block_named_4_name_11_same_thread",
    )
    concrete_body.should contain("literal 99 : Int32")
    concrete_body.should match(/call %\d+\.Proc#call\(\) : 4/)
  end

  it "counts positional and named values for a forwarded block call" do
    hir = named_block_forwarding_hir(<<-CRYSTAL)
      class MixedNamedBlockScheduler
        def spawn(seed : Int32, *, name : String, same_thread : Bool, &block : -> Int32) : Int32
          return seed + 100 if same_thread
          seed + block.call
        end
      end

      scheduler = MixedNamedBlockScheduler.new
      scheduler.spawn(2, name: "mixed", same_thread: false) { 40 }
      CRYSTAL

    # This call has one positional value and two named values. The selected
    # block-taking body must retain both its branch and Proc invocation.
    hir.should contain("literal 100 : Int32")
    hir.should contain("Proc#call() : 4")
  end

  it "retains named source shape for a module-interface virtual target" do
    hir = named_block_forwarding_hir(<<-CRYSTAL)
      module NamedVirtualShape
        module Scheduler
          abstract def spawn(*, name : String, same_thread : Bool, &block : -> Int32) : Int32
        end

        class ParallelScheduler
          include Scheduler

          def spawn(*, name : String, same_thread : Bool, &block : -> Int32) : Int32
            return 99 if same_thread
            block.call
          end
        end
      end

      def dispatch(scheduler : NamedVirtualShape::Scheduler, name : String, same_thread : Bool, &block : -> Int32) : Int32
        scheduler.spawn(name: name, same_thread: same_thread, &block)
      end

      dispatch(NamedVirtualShape::ParallelScheduler.new, "outer", false) { 41 }
      CRYSTAL

    hir.should match(/call %\d+\.NamedVirtualShape::Scheduler#spawn\$String_Bool_block(?:_named_4_name_11_same_thread)?\(/)
    hir.should contain("[virtual]")
    concrete_body = named_block_forwarding_hir_function(
      hir,
      "NamedVirtualShape::ParallelScheduler#spawn$String_Bool_block_named_4_name_11_same_thread",
    )
    concrete_body.should contain("literal 99 : Int32")
    concrete_body.should contain("Proc#call() : 4")
  end

  it "does not replay a named virtual target into a different overload shape" do
    hir = named_block_forwarding_hir(<<-CRYSTAL)
      module NamedVirtualShapeControls
        module Scheduler
          abstract def spawn(*, name : String, same_thread : Bool, &block : -> Int32) : Int32
        end

        class ParallelScheduler
          include Scheduler

          def spawn(*, name : String, same_thread : Bool, &block : -> Int32) : Int32
            block.call
          end

          def spawn(seed : Int32, *, name : String, same_thread : Bool, &block : -> Int32) : Int32
            seed + block.call
          end

          def spawn(*, title : String, same_thread : Bool, &block : -> Int32) : Int32
            block.call + 1
          end

          def spawn(*, name : String, same_thread : Bool) : Int32
            7
          end
        end
      end

      def dispatch(scheduler : NamedVirtualShapeControls::Scheduler, name : String, same_thread : Bool, &block : -> Int32) : Int32
        scheduler.spawn(name: name, same_thread: same_thread, &block)
      end

      dispatch(NamedVirtualShapeControls::ParallelScheduler.new, "outer", false) { 41 }
      CRYSTAL

    concrete_body = named_block_forwarding_hir_function(
      hir,
      "NamedVirtualShapeControls::ParallelScheduler#spawn$String_Bool_block_named_4_name_11_same_thread",
    )
    concrete_body.should contain("Proc#call() : 4")
    hir.should_not contain("func @NamedVirtualShapeControls::ParallelScheduler#spawn$Int32_String_Bool_block_named_4_name_11_same_thread(")
    hir.should_not contain("func @NamedVirtualShapeControls::ParallelScheduler#spawn$String_Bool_block_named_5_title_11_same_thread(")
    hir.should_not contain("func @NamedVirtualShapeControls::ParallelScheduler#spawn$String_Bool_named_4_name_11_same_thread(")
  end
end
