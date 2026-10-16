#!/usr/bin/env bash
# Preserve a block-dependent result annotation selected from an included module.
# The route callback forces return inference before ordinary body lowering;
# generic wrappers, declaration namespaces, alternating owner bindings and a
# local override guard both result inference and the native ABI.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${COMPILER:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$RUN_SAFE" && -x "$COMPILER" && -x "$ORIGINAL" ]] || {
  echo "usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0 /path/to/adamas" >&2
  exit 2
}
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/included-block-result.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT
cat >"$WORK_DIR/consumer.cr" <<'CRYSTAL'
module LavinMQ
  module Auth
    abstract class BaseUser
      alias Permissions = NamedTuple(config: Regex, read: Regex, write: Regex)
      abstract def name : String
      abstract def permissions : Hash(String, Permissions)

      def permissions_details(vhost, p)
        {user: name, vhost: vhost, configure: p[:config], read: p[:read], write: p[:write]}
      end
    end

    class User < BaseUser
      getter name : String
      getter permissions : Hash(String, Permissions) = Hash(String, Permissions).new

      def initialize(@name)
        @permissions["/"] = {config: /^$/, read: /read/, write: /write/}
      end

      def permissions_details
        @permissions.map { |k, p| permissions_details(k, p) }
      end
    end
  end
end

class UsersController
  def initialize
    @users = {"guest" => LavinMQ::Auth::User.new("guest")}
  end

  private def get(path, &)
    yield 1, {"name" => "guest", "vhost" => "/"}
  end

  private def user(context, params, key = "name")
    u = @users[params[key]]?
    raise "missing" unless u
    u
  end

  def register_routes
    get "/permissions" do |context, params|
      u = user(context, params)
      if vhost = params["vhost"]?
        puts u.permissions_details.find { |p| p[:vhost] == vhost }.not_nil![:user]
      else
        puts "no vhost"
      end
      context
    end
  end
end

UsersController.new.register_routes

class ProjectionBox(T)
  getter value : T
  def initialize(@value : T)
  end
end

module OwnerProjection
  def project(&block : Int32 -> U) : ProjectionBox(U) forall U
    ProjectionBox(U).new(yield 7)
  end
end

class ProjectionUser
  include OwnerProjection
end

class ProjectionOverride < ProjectionUser
  def project(&block : Int32 -> U) : U forall U
    yield 9
  end
end

puts ProjectionUser.new.project { |i| "box#{i}" }.value
puts ProjectionUser.new.project { |i| i + 1 }.value
puts ProjectionOverride.new.project { |i| "override#{i}" }

module BlockProjectionScope
  class Envelope(T)
    getter value : T
    def initialize(@value : T)
    end
  end

  module Projector
    def project(&block : Int32 -> U) : Envelope(U) forall U
      Envelope(U).new(yield 7)
    end
  end
end

class Envelope(T)
  getter value : Int32
  def initialize
    @value = 99
  end
end

class OwnerProjectionConsumer
  include BlockProjectionScope::Projector
end

puts OwnerProjectionConsumer.new.project { |i| "inner#{i}" }.value
puts OwnerProjectionConsumer.new.project { |i| i + 1 }.value

module BlockProjectionScope
  class Pair(A, B)
    getter first : A
    getter second : B
    def initialize(@first : A, @second : B)
    end
  end

  module GenericProjector(T)
    def pair(value : T, &block : T -> U) : Pair(T, U) forall U
      Pair(T, U).new(value, yield value)
    end
  end
end

class IntegerProjectionConsumer
  include BlockProjectionScope::GenericProjector(Int32)
end

class StringProjectionConsumer
  include BlockProjectionScope::GenericProjector(String)
end

integer_pair = IntegerProjectionConsumer.new.pair(3) { |i| "num#{i}" }
puts integer_pair.first
puts integer_pair.second
string_pair = StringProjectionConsumer.new.pair("four") { |s| s.size }
puts string_pair.first
puts string_pair.second
CRYSTAL
cat >"$WORK_DIR/expected.txt" <<'EXPECTED'
guest
box7
8
override9
inner7
8
3
num3
four
4
EXPECTED

build_and_run() {
  local stage="$1" compiler="$2"
  local binary="$WORK_DIR/$stage.bin"
  local -a command
  if [[ "$stage" == original ]]; then
    command=("$compiler" build "$WORK_DIR/consumer.cr" -o "$binary" --no-debug
             --link-flags="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}")
  else
    command=("$compiler" "$WORK_DIR/consumer.cr" --no-ast-cache --no-llvm-cache --no-debug -o "$binary")
  fi
  if ! env "CRYSTAL_CACHE_DIR=$WORK_DIR/$stage.cache" \
      "ADAMAS_EXTRA_LINK_FLAGS=${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      "$RUN_SAFE" "${command[0]}" 240 8192 "${command[@]:1}" \
      >"$WORK_DIR/$stage.build.log" 2>&1; then
    tail -35 "$WORK_DIR/$stage.build.log" >&2
    return 1
  fi
  rm -rf "$WORK_DIR/$stage.cache"
  if ! env RUN_SAFE_PASSTHROUGH_STDIO=1 \
      "$RUN_SAFE" "$binary" 15 1024 >"$WORK_DIR/$stage.stdout" \
      2>"$WORK_DIR/$stage.run.log"; then
    tail -35 "$WORK_DIR/$stage.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$stage.run.log"
  diff -u "$WORK_DIR/expected.txt" "$WORK_DIR/$stage.stdout"
}

build_and_run original "$ORIGINAL"
build_and_run candidate "$COMPILER"
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"
printf 'PASS: included block results preserve declaration scope, generic bindings and native values\n'
