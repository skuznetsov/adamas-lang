require "spec"
require "file_utils"
require "json"

private def run_reachability(ll : String)
  root = File.expand_path("..", __DIR__)
  script = File.join(root, "scripts", "llvm_function_reachability.py")
  workdir = File.join(Dir.tempdir, "adamas_llvm_reach_#{Process.pid}_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(workdir)
  input = File.join(workdir, "module.ll")
  outdir = File.join(workdir, "out")
  File.write(input, ll)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run("python3", [script, "--ll", input, "--out-dir", outdir], output: stdout, error: stderr)
  {status, stdout.to_s, stderr.to_s, outdir, workdir}
end

private def rows(path : String)
  lines = File.read(path).lines
  headers = lines.shift.split('\t')
  lines.reject(&.empty?).map do |line|
    values = line.chomp.split('\t')
    headers.zip(values).to_h
  end
end

describe "llvm_function_reachability.py" do
  it "parses quoted and unquoted symbols, declarations, and global address roots" do
    ll = <<-LL
      @llvm.used = appending global [1 x ptr] [ptr @"*Quoted#entry:Int32"]

      define internal void @"*Quoted#entry:Int32"() {
      entry:
        call void @plain_target()
        %text = alloca [14 x i8]
        store [14 x i8] c"@not_a_symbol\\00", ptr %text
        ; @comment_only_is_not_a_reference
        ret void
      }
      define void @plain_target() {
      entry:
        ret void
      }
      declare void @"*External#missing:Nil"()
      define void @main() {
      entry:
        call void @"*External#missing:Nil"()
        ret void
      }
    LL
    result = run_reachability(ll)
    result[0].success?.should be_true, result[2]
    function_rows = rows(File.join(result[3], "functions.tsv"))
    quoted = function_rows.find! { |row| row["raw"] == "*Quoted#entry:Int32" }
    quoted["kind"].should eq("define")
    quoted["linkage"].should eq("internal")
    quoted["reachable"].should eq("true")
    function_rows.find! { |row| row["raw"] == "plain_target" }["linkage"].should eq("external")
    function_rows.find! { |row| row["raw"] == "*External#missing:Nil" }["kind"].should eq("declare")
    function_rows.find! { |row| row["raw"] == "*External#missing:Nil" }["reachable"].should eq("true")
    globals = rows(File.join(result[3], "global_refs.tsv"))
    globals.any? { |row| row["target"] == "*Quoted#entry:Int32" }.should be_true
    File.read(File.join(result[3], "edges.tsv")).should_not contain("not_a_symbol")
    summary = JSON.parse(File.read(File.join(result[3], "summary.json")))
    summary["linkage"]["internal"].as_i.should eq(1)
    summary["linkage"]["external"].as_i.should eq(3)
    FileUtils.rm_rf(result[4]) if Dir.exists?(result[4])
  end

  it "separates vdispatch and source callers and keeps an unreachable cycle unreachable" do
    ll = <<-LL
      define void @target() {
      entry:
        ret void
      }
      declare void @__gxx_personality_v0()
      define void @header_caller() personality ptr @__gxx_personality_v0 {
      entry:
        ret void
      }
      define void @source_caller() {
      entry:
        call void @target()
        ret void
      }
      define void @__vdispatch__Target$Hrun$$T1() {
      entry:
        call void @target()
        ret void
      }
      define void @dead_a() {
      entry:
        call void @dead_b()
        ret void
      }
      define void @dead_b() {
      entry:
        call void @dead_a()
        ret void
      }
      define void @main() {
      entry:
        call void @source_caller()
        call void @__vdispatch__Target$Hrun$$T1()
        call void @header_caller()
        ret void
      }
    LL
    result = run_reachability(ll)
    result[0].success?.should be_true, result[2]
    function_rows = rows(File.join(result[3], "functions.tsv"))
    target = function_rows.find! { |row| row["raw"] == "target" }
    target["incoming_unique_callers"].should eq("__vdispatch__Target$Hrun$$T1;source_caller")
    target["incoming_source_callers"].should eq("source_caller")
    target["incoming_vdispatch_callers"].should eq("__vdispatch__Target$Hrun$$T1")
    target["reachable"].should eq("true")
    personality = function_rows.find! { |row| row["raw"] == "__gxx_personality_v0" }
    personality["incoming_unique_callers"].should eq("header_caller")
    personality["reachable"].should eq("true")
    function_rows.find! { |row| row["raw"] == "dead_a" }["reachable"].should eq("false")
    function_rows.find! { |row| row["raw"] == "dead_b" }["reachable"].should eq("false")
    FileUtils.rm_rf(result[4]) if Dir.exists?(result[4])
  end

  it "counts global initializer references separately from function-body edges" do
    ll = <<-LL
      @table = global [1 x ptr] [ptr @address_taken]
      define void @address_taken() {
      entry:
        ret void
      }
      define void @main() {
      entry:
        ret void
      }
    LL
    result = run_reachability(ll)
    result[0].success?.should be_true, result[2]
    function_rows = rows(File.join(result[3], "functions.tsv"))
    address = function_rows.find! { |row| row["raw"] == "address_taken" }
    address["global_ref_count"].should eq("1")
    address["incoming_unique_callers"].should eq("")
    address["reachable"].should eq("true")
    File.read(File.join(result[3], "edges.tsv")).should_not contain("address_taken")
    FileUtils.rm_rf(result[4]) if Dir.exists?(result[4])
  end
end
