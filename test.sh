#!/usr/bin/env bash
set -euo pipefail

echo "Changing to 10 blocks a day for testing..."

find ./contracts -name "*Template.sol" -print0 | xargs -0 sed -i "s/BLOCKS_PER_DAY = 6500/BLOCKS_PER_DAY = 10/g"

npx hardhat test "$@"

find ./contracts -name "*Template.sol" -print0 | xargs -0 sed -i "s/BLOCKS_PER_DAY = 10/BLOCKS_PER_DAY = 6500/g"

echo "Changing back to 6500 blocks a day"
