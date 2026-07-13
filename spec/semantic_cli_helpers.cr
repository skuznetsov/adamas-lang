require "spec"
require "../src/compiler/cli"

module SemanticCliSpecHelpers
  def with_temp_shadow_project(files : Hash(String, String), &)
    dir = File.join(Dir.tempdir, "semantic_shadow_cli_#{Random::Secure.hex(6)}")
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

  def with_semantic_shadow_env(&)
    previous = ENV["ADAMAS_SEMANTIC_SHADOW"]?
    ENV["ADAMAS_SEMANTIC_SHADOW"] = "1"

    begin
      yield
    ensure
      if previous
        ENV["ADAMAS_SEMANTIC_SHADOW"] = previous
      else
        ENV.delete("ADAMAS_SEMANTIC_SHADOW")
      end
    end
  end

  def with_semantic_compile_env(&)
    previous = ENV["ADAMAS_SEMANTIC_COMPILE"]?
    ENV["ADAMAS_SEMANTIC_COMPILE"] = "1"

    begin
      yield
    ensure
      if previous
        ENV["ADAMAS_SEMANTIC_COMPILE"] = previous
      else
        ENV.delete("ADAMAS_SEMANTIC_COMPILE")
      end
    end
  end

  def with_semantic_shadow_strict_env(&)
    previous_shadow = ENV["ADAMAS_SEMANTIC_SHADOW"]?
    previous_strict = ENV["ADAMAS_SEMANTIC_SHADOW_STRICT"]?
    ENV["ADAMAS_SEMANTIC_SHADOW"] = "1"
    ENV["ADAMAS_SEMANTIC_SHADOW_STRICT"] = "1"

    begin
      yield
    ensure
      if previous_shadow
        ENV["ADAMAS_SEMANTIC_SHADOW"] = previous_shadow
      else
        ENV.delete("ADAMAS_SEMANTIC_SHADOW")
      end

      if previous_strict
        ENV["ADAMAS_SEMANTIC_SHADOW_STRICT"] = previous_strict
      else
        ENV.delete("ADAMAS_SEMANTIC_SHADOW_STRICT")
      end
    end
  end

end
