require "spec"
require "../src/compiler/cli"

private def with_temp_semantic_compile_project(files : Hash(String, String), &)
  dir = File.join(Dir.tempdir, "semantic_compile_cli_#{Random::Secure.hex(6)}")
  Dir.mkdir_p(dir)
  files.each do |name, source|
    File.write(File.join(dir, name), source)
  end

  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir) if Dir.exists?(dir)
  end
end

private def with_semantic_compile_env_for_tz_alias(&)
  previous = ENV["CRYSTAL_V2_SEMANTIC_COMPILE"]?
  ENV["CRYSTAL_V2_SEMANTIC_COMPILE"] = "1"

  begin
    yield
  ensure
    if previous
      ENV["CRYSTAL_V2_SEMANTIC_COMPILE"] = previous
    else
      ENV.delete("CRYSTAL_V2_SEMANTIC_COMPILE")
    end
  end
end

describe CrystalV2::Compiler::CLI do
  it "keeps semantic compile prepass green for stdlib record union aliases inside class-owned module reopens" do
    with_temp_semantic_compile_project({
      "main.cr" => <<-'CRYSTAL',
        require "/Users/sergey/Projects/Crystal/crystal_v2_repo/src/stdlib/object/properties"
        require "/Users/sergey/Projects/Crystal/crystal_v2_repo/src/stdlib/macros"

        struct Object
        end

        struct Value
        end

        struct Number < Value
        end

        struct Int8 < Number
        end

        struct Int16 < Number
        end

        struct Int32 < Number
        end

        struct Int64 < Number
        end

        struct Time
        end

        module Time::TZ
          record Julian1, ordinal : Int16, time : Int32 do
            def unix_date_in_year(year : Int32) : Int64
              year.to_i64 + ordinal
            end
          end

          record Julian0, ordinal : Int16, time : Int32 do
            def unix_date_in_year(year : Int32) : Int64
              year.to_i64 + ordinal - 1
            end
          end

          record MonthWeekDay, month : Int8, week : Int8, day : Int8, time : Int32 do
            def unix_date_in_year(year : Int32) : Int64
              year.to_i64 + month + week + day
            end
          end

          alias POSIXTransition = Julian1 | Julian0 | MonthWeekDay

          def self.probe(t : POSIXTransition)
            t.unix_date_in_year(2024) + t.time
          end
        end

        Time::TZ.probe(Time::TZ::Julian0.new(0_i16, 0))
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env_for_tz_alias do
        cli = CrystalV2::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end
end
