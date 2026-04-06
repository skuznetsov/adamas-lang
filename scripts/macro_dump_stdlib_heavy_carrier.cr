# Stdlib-heavy carrier: pulls JSON/URI/time/CSV macro surfaces beyond prelude alone.
# Avoid require "big" here (links libgmp; breaks link on machines without GMP).
# For a full link test: install gmp or use: crystal_v2 ... --no-link -o /tmp/out.o
require "json"
require "uri"
require "time"
require "csv"

1
