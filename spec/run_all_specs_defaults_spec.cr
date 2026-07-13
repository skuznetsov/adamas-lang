require "spec"

describe "scripts/run_all_specs.sh defaults" do
  it "uses the collision-safe sequential 8 GiB defaults while retaining positional overrides" do
    script = File.read(File.expand_path("../scripts/run_all_specs.sh", __DIR__))

    script.should contain(%(JOBS="${1:-1}"))
    script.should contain(%(TIMEOUT="${2:-300}"))
    script.should contain(%(MAX_MEM_MB="${3:-8192}"))
    script.should contain(%(PRODUCED_STAGE_TIMEOUT="${ADAMAS_PRODUCED_STAGE_SPEC_TIMEOUT:-900}"))
    script.should contain(%(CRYSTAL_WORKERS="${CRYSTAL_WORKERS:-1}"))
    script.should contain("export CRYSTAL_WORKERS")
    script.should contain(%(Usage: scripts/run_all_specs.sh [jobs] [timeout_sec] [max_mem_mb] [paths...]))
    script.should contain(%(JOBS="${1:-))
    script.should contain(%(MAX_MEM_MB="${3:-))
  end
end
