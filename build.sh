#!/bin/bash
set -e

echo "[Building Zenoo C Extension...]"
cd ext/zenoo
ruby extconf.rb
make clean
make
cd ../..
echo ""
echo "======================================================="
echo " Zenoo C Extension (zenoo.so) Build Successful!"
echo " Run demo:"
echo "   ruby -Ilib examples/demo_ruby_sdf.rb"
echo "   ruby -Ilib examples/test_gc.rb"
echo "======================================================="
