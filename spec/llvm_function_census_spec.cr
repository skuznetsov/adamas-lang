require "spec"
require "file_utils"

def run_llvm_census(original : String, adamas : String, extra : Array(String) = [] of String)
  root = File.expand_path("..", __DIR__)
  script = File.join(root, "scripts", "compare_llvm_functions.py")
  workdir = File.join(Dir.tempdir, "adamas_llvm_census_#{Process.pid}_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(workdir)
  original_path = File.join(workdir, "original.ll")
  adamas_path = File.join(workdir, "adamas.ll")
  outdir = File.join(workdir, "out")
  File.write(original_path, original)
  File.write(adamas_path, adamas)
  args = ["--original-ll", original_path, "--adamas-ll", adamas_path, "--out-dir", outdir]
  extra.each { |arg| args << arg }
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run("python3", [script] + args, output: stdout, error: stderr)
  {status, stdout.to_s, stderr.to_s, outdir, workdir}
end

def assert_tsv_shape(path : String)
  lines = File.read(path).lines
  lines.empty?.should be_false
  header = lines.first.split("\t")
  header.uniq.size.should eq(header.size)
  lines[1..].each do |line|
    line.split("\t").size.should eq(header.size)
  end
end

describe "compare_llvm_functions.py" do

  it "matches structured original methods while retaining categories and declarations" do
    original = <<-LL
      ; quoted names exercise LLVM string escaping and nested type parsing
      define internal i32 @"*String#size:Int32"(ptr %self) {
      entry: ret i32 0
      }
      define internal %"(Int32 | Nil)" @"*QuotedReturn#value:Int32"(ptr %self) {
      entry: ret i32 0
      }
      define internal ptr @"*String::new<Int32>:String"(i32 %value) {
      entry: ret ptr null
      }
      define internal ptr @"*Child@Parent::new<Int32>:Parent"(ptr %value) {
      entry: ret ptr null
      }
      define internal i32 @"*Child@Parent#<<<Int32, Tuple(String, Array(Int32 | Nil))>:Int32"(ptr %self, i32 %x) {
      entry: ret i32 0
      }
      define internal i32 @"*String#each<Char, &Proc(Char, Nil)>:Int32"(ptr %self, ptr %block) {
      entry: ret i32 0
      }
      define internal i32 @"*Foo#<=>:Int32"(ptr %self, ptr %other) {
      entry: ret i32 0
      }
      define internal i32 @"*IO::FileDescriptor@IO#read_char_with_bytesize<Nil>:Char"(ptr %self, ptr %arg) {
      entry: ret i32 0
      }
      define internal i32 @"*IO::FileDescriptor@IO#read_char_with_bytesize<Nil>:UInt8"(ptr %self, ptr %arg) {
      entry: ret i32 0
      }
      define internal i32 @"*Bad#broken<Int32, Tuple(String>:Int32"(ptr %self) {
      entry: ret i32 0
      }
      declare ptr @"*External::missing:Nil"()
      define internal void @"~procFoo@file.cr:12"() {
      entry: ret void
      }
      define internal void @__crystal_block_proc_4() {
      entry: ret void
      }
      declare ptr @puts(ptr)
      declare ptr @"puts\\2Ewrapped"(ptr)
      define void @main() {
      entry: ret void
      }
    LL
    adamas = <<-LL
      define i32 @String$Hsize(ptr %self) {
      entry: ret i32 0
      }
      define i32 @QuotedReturn$Hvalue(ptr %self) {
      entry: ret i32 0
      }
      define ptr @String$Dnew$$Int32(ptr %value) {
      entry: ret ptr null
      }
      define ptr @Parent$Dnew$$Int32(ptr %value) {
      entry: ret ptr null
      }
      define i32 @Parent$H$SHL$$Int32_Tuple$LString$C$_Array$LNil$_$OR$_Int32$R$R(ptr %self, i32 %x) {
      entry: ret i32 0
      }
      define i32 @String$Heach$$Char_block(ptr %self, ptr %block) {
      entry: ret i32 0
      }
      define i32 @Foo$H$CMP(ptr %self, ptr %other) {
      entry: ret i32 0
      }
      define i32 @IO$Hread_char_with_bytesize$$arity1(ptr %self, ptr %arg) {
      entry: ret i32 0
      }
      define i32 @IO$Hgets$$Char_Int32$$arity3_super(ptr %self, ptr %arg) {
      entry: ret i32 0
      }
      define ptr @__vdispatch__Child$Hfoo$$T123(ptr %self) {
      entry: ret ptr null
      }
      declare ptr @puts(ptr)
      declare ptr @"puts\\2Ewrapped"(ptr)
      define void @main() {
      entry: ret void
      }
    LL
    result = run_llvm_census(original, adamas)
    result[0].success?.should be_true, result[2]
    File.exists?(File.join(result[3], "summary.json")).should be_true
    summary = File.read(File.join(result[3], "summary.json"))
    summary.should contain(%("original"))
    summary.should contain(%("adamas"))
    summary.should contain(%("define"))
    summary.should contain(%("declare"))
    summary.should contain(%("vdispatch"))
    summary.should contain(%("closure"))
    summary.should contain(%("extern"))
    matches = File.read(File.join(result[3], "matches.tsv"))
    matches.should contain("String#size")
    matches.should contain("QuotedReturn#value")
    matches.should contain("mismatch")
    matches.should contain("class")
    matches.should contain("receiver")
    matches.should contain("impl_full")
    matches.should contain("impl_full_class")
    matches.should contain("$SHL")
    matches.should contain("$CMP")
    matches.should contain("puts")
    matches.should contain("puts.wrapped")
    matches.should contain("raw_exact")
    conflicts = File.read(File.join(result[3], "abi_conflicts.tsv"))
    conflicts.should contain("%\"(Int32 | Nil)\"|ptr")
    summary.should contain(%("adamas_families"))
    summary.should contain(%("entry"))
    summary.should contain(%("abi_mismatches"))
    summary.should contain(%("linkage_states"))
    summary.should contain(%("provisional_collisions"))
    File.read(File.join(result[3], "provisional_matches.tsv")).should contain("read_char_with_bytesize")
    File.read(File.join(result[3], "provisional_matches.tsv")).should contain("arity1")
    File.read(File.join(result[3], "original_only.tsv")).should contain("unbalanced type delimiters")
    File.read(File.join(result[3], "adamas_only.tsv")).should contain("IO$Hgets$$Char_Int32$$arity3_super")
    File.read(File.join(result[3], "collisions.tsv")).should contain("many_original_one_adamas_provisional")
    assert_tsv_shape(File.join(result[3], "matches.tsv"))
    assert_tsv_shape(File.join(result[3], "provisional_matches.tsv"))
    File.read(File.join(result[3], "original_only.tsv")).should contain("External::missing")
    File.read(File.join(result[3], "original_only.tsv")).should_not contain("puts")
    FileUtils.rm_rf(result[4]) if Dir.exists?(result[4])
  end

  it "does not silently decode the non-prefix-free $LTuple token" do
    original = "define i32 @\"*Array(Tuple(Int32, String))#size:Int32\"(ptr %self) { ret i32 0 }\n"
    adamas = "define i32 @Array$LTuple$LInt32$C$_String$R$R$Hsize(ptr %self) { ret i32 0 }\n"
    result = run_llvm_census(original, adamas)
    result[0].success?.should be_true, result[2]
    ambiguous = File.read(File.join(result[3], "ambiguous.tsv"))
    ambiguous.should contain("LTuple")
    ambiguous.should contain("ambiguous")
    File.read(File.join(result[3], "matches.tsv")).should_not contain("Array<uple")
    FileUtils.rm_rf(result[4]) if Dir.exists?(result[4])
  end

  it "selects the implementation-owner tier and reports receiver fanout" do
    original = "define i32 @\"*Child@Parent#to_s:String\"(ptr %self) { ret i32 0 }\n"
    adamas = <<-LL
      define i32 @Child$Hto_s(ptr %self) { ret i32 0 }
      define i32 @Parent$Hto_s(ptr %self) { ret i32 0 }
    LL
    result = run_llvm_census(original, adamas)
    result[0].success?.should be_true, result[2]
    matches = File.read(File.join(result[3], "matches.tsv"))
    matches.should contain("Parent$Hto_s")
    matches.should contain("impl_full")
    File.read(File.join(result[3], "original_only.tsv")).should_not contain("to_s")
    File.read(File.join(result[3], "collisions.tsv")).should contain("candidate_fanout")
    File.read(File.join(result[3], "adamas_only.tsv")).should contain("Child$Hto_s")
    FileUtils.rm_rf(result[4]) if Dir.exists?(result[4])
  end

  it "reports duplicate and raw-symbol collisions deterministically" do
    original = <<-LL
      define i32 @"*Foo#bar:Int32"(ptr %self) { ret i32 0 }
      define i32 @"*Foo#bar:Int32"(ptr %self) { ret i32 0 }
    LL
    adamas = <<-LL
      define i32 @Foo$Hbar$$Int32(ptr %self) { ret i32 0 }
      declare i32 @Foo$Hbar$$Int32(ptr %self)
      define i32 @Foo$Hbar$$Int32(ptr %self) { ret i32 0 }
    LL
    result = run_llvm_census(original, adamas)
    result[0].success?.should be_true, result[2]
    collisions = File.read(File.join(result[3], "collisions.tsv"))
    collisions.should contain("raw_duplicate")
    collisions.should contain("semantic_duplicate")
    collisions.should contain("Foo#bar")
    FileUtils.rm_rf(result[4]) if Dir.exists?(result[4])
  end

  it "keeps absolute roots, cross-linkage matches, cardinality, and path-generated rows explicit" do
    original = <<-LL
      define i32 @"*Pointer#size:Int32"(ptr %self) { ret i32 0 }
      declare ptr @"*Cross::new:Int32"()
      define i32 @"*Foo#dup:Int32"(ptr %self) { ret i32 0 }
      define i32 @"*Foo#dup:UInt32"(ptr %self) { ret i32 0 }
      define i32 @"*/tmp/generated.cr::Hidden#run:Int32"(ptr %self) { ret i32 0 }
    LL
    adamas = <<-LL
      define i32 @$CCPointer$Hsize(ptr %self) { ret i32 0 }
      define ptr @Cross$Dnew() { ret ptr null }
      define i32 @Foo$Hdup(ptr %self) { ret i32 0 }
      define ptr @__vdispatch__Foo$Hdup$$T3(ptr %self) { ret ptr null }
      define i32 @Broken$ZZbar(ptr %self) { ret i32 0 }
    LL
    result = run_llvm_census(original, adamas)
    result[0].success?.should be_true, result[2]
    matches = File.read(File.join(result[3], "matches.tsv"))
    matches.should contain("receiver_full_absolute")
    matches.should contain("declare_to_define")
    collisions = File.read(File.join(result[3], "collisions.tsv"))
    collisions.should contain("many_original_one_adamas")
    summary = File.read(File.join(result[3], "summary.json"))
    summary.should contain(%("matched_pairs"))
    summary.should contain(%("matched_original_unique"))
    summary.should contain(%("matched_adamas_unique"))
    summary.should contain(%("vdispatch"))
    original_only = File.read(File.join(result[3], "original_only.tsv"))
    original_only.should contain("path_generated")
    ambiguous = File.read(File.join(result[3], "ambiguous.tsv"))
    ambiguous.should contain("Broken$ZZbar")
    FileUtils.rm_rf(result[4]) if Dir.exists?(result[4])
  end
end
