require "spec"
require "file_utils"
require "random/secure"

require "./support/server_helper"

private def apply_formatting_edit(source : String, response : JSON::Any) : String
  edits = response["result"].as_a
  edits.size.should eq(1)

  edit = edits.first
  start_offset = utf16_position_to_byte_offset(
    source,
    edit["range"]["start"]["line"].as_i,
    edit["range"]["start"]["character"].as_i
  )
  end_offset = utf16_position_to_byte_offset(
    source,
    edit["range"]["end"]["line"].as_i,
    edit["range"]["end"]["character"].as_i
  )

  source.byte_slice(0, start_offset) + edit["newText"].as_s + source.byte_slice(end_offset, source.bytesize - end_offset)
end

private def utf16_position_to_byte_offset(text : String, line : Int32, character : Int32) : Int32
  offsets = [0]
  text.to_slice.each_with_index do |byte, idx|
    offsets << (idx + 1) if byte == '\n'.ord
  end

  line_start = offsets[line]
  line_end = line + 1 < offsets.size ? offsets[line + 1] : text.bytesize
  line_text = text.byte_slice(line_start, line_end - line_start)

  byte_offset = line_start
  units = 0
  line_text.each_char do |char|
    break if units >= character
    char_units = char.ord > 0xFFFF ? 2 : 1
    break if units + char_units > character
    byte_offset += char.bytesize
    units += char_units
  end
  byte_offset
end

describe CrystalV2::Compiler::LSP::Server do
  around_each do |example|
    prev = ENV["CRYSTALV2_LSP_FORCE_STUB"]?
    ENV["CRYSTALV2_LSP_FORCE_STUB"] = "1"
    begin
      example.run
    ensure
      if prev
        ENV["CRYSTALV2_LSP_FORCE_STUB"] = prev
      else
        ENV.delete("CRYSTALV2_LSP_FORCE_STUB")
      end
    end
  end

  it "reuses formatting responses for unchanged document versions" do
    dir = File.join(Dir.tempdir, "lsp_format_cache_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "main.cr")
    source = "x=1\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
    )
    uri = server.spec_store_document(source, dir, path)

    first = server.spec_formatting(uri)
    first["result"].as_a.size.should eq(1)
    server.spec_formatting_cache_version(uri).should eq(1)

    second = server.spec_formatting(uri)
    second.to_json.should eq(first.to_json)
    server.spec_formatting_cache_version(uri).should eq(1)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "returns a minimal edit for small formatting changes" do
    dir = File.join(Dir.tempdir, "lsp_format_minimal_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "main.cr")
    source = "x=1\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
    )
    uri = server.spec_store_document(source, dir, path)

    response = server.spec_formatting(uri)
    edits = response["result"].as_a
    edits.size.should eq(1)

    edit = edits.first
    edit["range"]["start"]["line"].as_i.should eq(0)
    edit["range"]["start"]["character"].as_i.should eq(1)
    edit["range"]["end"]["line"].as_i.should eq(0)
    edit["range"]["end"]["character"].as_i.should eq(2)
    edit["newText"].as_s.should eq(" = ")
    apply_formatting_edit(source, response).should eq(CrystalV2::Compiler::Formatter.format(source))
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "returns UTF-16 positions for Unicode formatting edits" do
    dir = File.join(Dir.tempdir, "lsp_format_unicode_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "main.cr")

    server = CrystalV2::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
    )

    pi_source = "π=1\n"
    File.write(path, pi_source)
    pi_uri = server.spec_store_document(pi_source, dir, path)
    pi_response = server.spec_formatting(pi_uri)
    pi_edit = pi_response["result"].as_a.first
    pi_edit["range"]["start"]["character"].as_i.should eq(1)
    pi_edit["range"]["end"]["character"].as_i.should eq(2)
    apply_formatting_edit(pi_source, pi_response).should eq(CrystalV2::Compiler::Formatter.format(pi_source))

    emoji_path = File.join(dir, "emoji.cr")
    emoji_source = "😀=1\n"
    File.write(emoji_path, emoji_source)
    emoji_uri = server.spec_store_document(emoji_source, dir, emoji_path)
    emoji_response = server.spec_formatting(emoji_uri)
    emoji_edit = emoji_response["result"].as_a.first
    emoji_edit["range"]["start"]["character"].as_i.should eq(2)
    emoji_edit["range"]["end"]["character"].as_i.should eq(3)
    apply_formatting_edit(emoji_source, emoji_response).should eq(CrystalV2::Compiler::Formatter.format(emoji_source))
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "returns null for already formatted documents" do
    dir = File.join(Dir.tempdir, "lsp_format_null_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "main.cr")
    source = "x = 1\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
    )
    uri = server.spec_store_document(source, dir, path)

    response = server.spec_formatting(uri)
    response["result"].raw.should be_nil
    server.spec_formatting_cache_version(uri).should eq(1)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "invalidates cached formatting when document text changes" do
    dir = File.join(Dir.tempdir, "lsp_format_cache_invalidate_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "main.cr")
    source = "x=1\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
    )
    uri = server.spec_store_document(source, dir, path)

    server.spec_formatting(uri)
    server.spec_formatting_cache_version(uri).should eq(1)

    updated = "x = 1\n"
    changes = %([{"text":#{updated.to_json}}])
    server.spec_did_change(uri, 2, changes)
    server.spec_formatting_cache_version(uri).should be_nil

    server.spec_formatting(uri)
    server.spec_formatting_cache_version(uri).should eq(2)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "uses the same minimal response shape for range formatting" do
    dir = File.join(Dir.tempdir, "lsp_range_format_minimal_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "main.cr")
    source = "x=1\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
    )
    uri = server.spec_store_document(source, dir, path)

    response = server.spec_range_formatting(uri, 0, 0, 0, source.bytesize)
    edits = response["result"].as_a
    edits.size.should eq(1)
    edits.first["newText"].as_s.should eq(" = ")
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "formats a partial range when the computed edit stays inside it" do
    dir = File.join(Dir.tempdir, "lsp_range_format_inside_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "main.cr")
    source = "x = 1\ny=2\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
    )
    uri = server.spec_store_document(source, dir, path)

    response = server.spec_range_formatting(uri, 1, 0, 1, 3)
    edits = response["result"].as_a
    edits.size.should eq(1)
    edits.first["range"]["start"]["line"].as_i.should eq(1)
    edits.first["range"]["start"]["character"].as_i.should eq(1)
    edits.first["range"]["end"]["line"].as_i.should eq(1)
    edits.first["range"]["end"]["character"].as_i.should eq(2)
    edits.first["newText"].as_s.should eq(" = ")
    apply_formatting_edit(source, response).should eq(CrystalV2::Compiler::Formatter.format(source))
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "returns null when a partial range excludes another formatting edit" do
    dir = File.join(Dir.tempdir, "lsp_range_format_outside_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "main.cr")
    source = "x=1\ny=2\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
    )
    uri = server.spec_store_document(source, dir, path)

    response = server.spec_range_formatting(uri, 1, 0, 1, 3)
    response["result"].raw.should be_nil
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "does not edit outside partial range formatting requests" do
    dir = File.join(Dir.tempdir, "lsp_range_format_partial_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "main.cr")
    source = "x=1\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
    )
    uri = server.spec_store_document(source, dir, path)

    response = server.spec_range_formatting(uri, 0, 0, 0, 1)
    response["result"].raw.should be_nil
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
