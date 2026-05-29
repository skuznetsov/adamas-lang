#!/bin/bash

CRYSTAL_CACHE_DIR="$(pwd)/.cache/debug/" crystal build -s -p -d src/adamas.cr -o bin/adamas_deb
