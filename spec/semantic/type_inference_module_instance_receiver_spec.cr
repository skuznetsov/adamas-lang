require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

include CrystalV2::Compiler::Frontend
include CrystalV2::Compiler::Semantic

private def infer_types(source : String)
  lexer = Lexer.new(source)
  parser = Parser.new(lexer)
  program = parser.parse_program

  analyzer = Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names

  engine = TypeInferenceEngine.new(program, name_result.identifier_symbols, analyzer.global_context.symbol_table)
  engine.infer_types

  {program, analyzer, engine}
end

describe TypeInferenceEngine do
  describe "module-owned instance methods" do
    it "defers eager body inference until an including receiver is available" do
      source = <<-CRYSTAL
        module Termios
        end

        lib LibC
          TCSANOW = 0
          ECHO    = 1_u64
          ECHOE   = 2_u64
          ECHOK   = 4_u64
          ECHONL  = 8_u64
          BRKINT  = 16_u64
          ISTRIP  = 32_u64
          ICRNL   = 64_u64
          IXON    = 128_u64
          OPOST   = 256_u64
          ICANON  = 512_u64
          ISIG    = 1024_u64
          IEXTEN  = 2048_u64

          alias TcflagT = UInt64

          struct Termios
            c_iflag : TcflagT
            c_oflag : TcflagT
            c_cflag : TcflagT
            c_lflag : TcflagT
          end

          fun tcgetattr(fd : Int32, termios_p : Termios*) : Int32
          fun tcsetattr(fd : Int32, optional_actions : Int32, termios_p : Termios*) : Int32
        end

        module Crystal::System::FileDescriptor
          private def system_echo(enable : Bool, mode = nil)
            new_mode = mode || system_tcgetattr
            flags = LibC::ECHO | LibC::ECHOE | LibC::ECHOK | LibC::ECHONL
            new_mode.c_lflag = enable ? (new_mode.c_lflag | flags) : (new_mode.c_lflag & ~flags)
            system_tcsetattr(LibC::TCSANOW, pointerof(new_mode))
          end

          private def system_tcgetattr
            termios = uninitialized LibC::Termios
            LibC.tcgetattr(fd, pointerof(termios))
            termios
          end

          private def system_tcsetattr(optional_actions, termios_p)
            LibC.tcsetattr(fd, optional_actions, termios_p)
          end

          private def system_raw(enable : Bool, mode = nil)
            new_mode = mode || system_tcgetattr
            new_mode.c_iflag |= LibC::BRKINT | LibC::ISTRIP | LibC::ICRNL | LibC::IXON
            new_mode.c_oflag |= LibC::OPOST
            new_mode.c_lflag |= LibC::ECHO | LibC::ECHOE | LibC::ECHOK | LibC::ECHONL | LibC::ICANON | LibC::ISIG | LibC::IEXTEN
            system_tcsetattr(LibC::TCSANOW, pointerof(new_mode))
          end
        end

        class Terminal
          include Crystal::System::FileDescriptor

          def initialize(@fd : Int32 = 0)
          end

          def fd : Int32
            @fd
          end

          def echo_off
            system_echo(false)
          end

          def raw_off
            system_raw(false)
          end
        end

        Terminal.new.echo_off
        Terminal.new.raw_off
      CRYSTAL

      _program, analyzer, engine = infer_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
    end

    it "treats libc integer aliases as numeric in struct field bitflag arithmetic" do
      source = <<-CRYSTAL
        lib LibC
          ECHO    = 0x00000008
          ECHOE   = 0x00000002
          ECHOK   = 0x00000004
          ECHONL  = 0x00000010
          BRKINT  = 0x00000002
          ISTRIP  = 0x00000020
          ICRNL   = 0x00000100
          IXON    = 0x00000200
          OPOST   = 0x00000001
          ICANON  = 0x00000100
          ISIG    = 0x00000080
          IEXTEN  = 0x00000400
          TCSANOW = 0

          alias ULong = UInt64
          alias TcflagT = ULong

          struct Termios
            c_iflag : TcflagT
            c_oflag : TcflagT
            c_cflag : TcflagT
            c_lflag : TcflagT
          end

          fun tcgetattr(fd : Int32, termios_p : Termios*) : Int32
          fun tcsetattr(fd : Int32, optional_actions : Int32, termios_p : Termios*) : Int32
        end

        module Crystal::System::FileDescriptor
          private def system_echo(enable : Bool, mode = nil)
            new_mode = mode || system_tcgetattr
            flags = LibC::ECHO | LibC::ECHOE | LibC::ECHOK | LibC::ECHONL
            new_mode.c_lflag = enable ? (new_mode.c_lflag | flags) : (new_mode.c_lflag & ~flags)
            system_tcsetattr(LibC::TCSANOW, pointerof(new_mode))
          end

          private def system_tcgetattr
            termios = uninitialized LibC::Termios
            LibC.tcgetattr(fd, pointerof(termios))
            termios
          end

          private def system_tcsetattr(optional_actions, termios_p)
            LibC.tcsetattr(fd, optional_actions, termios_p)
          end

          private def system_raw(enable : Bool, mode = nil)
            new_mode = mode || system_tcgetattr
            new_mode.c_iflag |= LibC::BRKINT | LibC::ISTRIP | LibC::ICRNL | LibC::IXON
            new_mode.c_oflag |= LibC::OPOST
            new_mode.c_lflag |= LibC::ECHO | LibC::ECHOE | LibC::ECHOK | LibC::ECHONL | LibC::ICANON | LibC::ISIG | LibC::IEXTEN
            system_tcsetattr(LibC::TCSANOW, pointerof(new_mode))
          end
        end

        class Terminal
          include Crystal::System::FileDescriptor

          def initialize(@fd : Int32 = 0)
          end

          def fd : Int32
            @fd
          end

          def echo_off
            system_echo(false)
          end

          def raw_off
            system_raw(false)
          end
        end

        Terminal.new.echo_off
        Terminal.new.raw_off
      CRYSTAL

      _program, analyzer, engine = infer_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
    end

    it "promotes libc integer aliases against numeric unions" do
      source = <<-CRYSTAL
        lib LibC
          alias ULong = UInt64
        end

        def probe(flag : LibC::ULong, other : UInt32 | UInt64)
          flag + other
        end

        probe(1_u64, 1_u32)
      CRYSTAL

      _program, analyzer, engine = infer_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
    end

    it "keeps if-branch local assignments visible to later statements in the same branch" do
      source = <<-CRYSTAL
        module Printer
          private def self.length_for_index(idx : UInt32)
            idx &+ 1
          end

          def self.probe(flag : Bool, idx : UInt32)
            if flag
              len = length_for_index(idx).to_i32!
              len - 1
            else
              0
            end
          end
        end

        Printer.probe(true, 1_u32)
      CRYSTAL

      program, analyzer, engine = infer_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "does not mix primitive and runtime UInt32 in helper unions" do
      source = <<-CRYSTAL
        struct UInt32
          def //(other : Int32)
            self
          end
        end

        module Printer
          private def self.index_for_exponent(e : UInt32)
            (e &+ 15) // 16
          end

          def self.probe(flag : Bool)
            idx = flag ? 0_u32 : index_for_exponent(1_u32)
            idx.to_i32!
          end
        end

        Printer.probe(false)
      CRYSTAL

      program, analyzer, engine = infer_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "keeps primitive helper return types primitive inside module class-method chains" do
      source = <<-CRYSTAL
        module Printer
          private def self.log10_pow2(e : Int32) : UInt32
            (e.to_u32! &* 78913) >> 18
          end

          private def self.index_for_exponent(e : UInt32)
            (e &+ 15) // 16
          end

          private def self.length_for_index(idx : UInt32)
            (log10_pow2(16 &* idx.to_i32!) &+ 25) // 9
          end

          def self.probe(e2 : Int32)
            idx = e2 < 0 ? 0_u32 : index_for_exponent(e2.to_u32!)
            len = length_for_index(idx).to_i32!
            len - 1
          end
        end

        Printer.probe(1)
      CRYSTAL

      program, analyzer, engine = infer_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "treats runtime numeric wrapper instances as primitive numeric operands in helper arithmetic" do
      source = <<-CRYSTAL
        struct UInt32
        end

        module Probe
          def self.wrap(digits : UInt32)
            c = digits &- 10000 &* (digits // 10000)
            c0 = (c % 100) << 1
            digits //= 100
            c1 = digits << 1
            {c0, c1}
          end
        end

        Probe.wrap(12345_u32)
      CRYSTAL

      program, analyzer, engine = infer_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Tuple(UInt32, UInt32)")
    end

    it "normalizes runtime String wrappers before string indexing" do
      source = <<-CRYSTAL
        struct String
        end

        module Probe
          def self.open_flag(mode : String)
            case mode[0]
            when 'r'
              1
            else
              0
            end
          end
        end

        Probe.open_flag("rb")
      CRYSTAL

      program, analyzer, engine = infer_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end
  end
end
