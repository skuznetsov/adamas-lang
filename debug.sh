#!/bin/bash

CRYSTAL_CACHE_DIR="$(pwd)/.cache/debug/" crystal build -s -p -d src/crystal_v2.cr -o bin/crystal_v2_deb
