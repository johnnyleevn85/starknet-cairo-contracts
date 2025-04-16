#!/bin/bash
pushd $(dirname "$0")/..

COLOR_OFF="\033[0m"
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
PURPLE='\033[1;35m'


printf "${YELLOW}Check Line Length...\n"
scripts/line_length.py
if  [ $? -ne 0 ]; then
    exit 1
fi


printf "${YELLOW}Run black...\n"
black  -l 100 --diff --check --color --diff .
if [ $? -eq 0 ]; then
    printf "${GREEN}Run black succeed\n"
else
    printf "${RED}Run black failed\n${PURPLE}Run 'black -l 100 .' to solve this problem.\n"
    exit 1
fi

printf "${YELLOW}Building contracts...\n"
scarb clean
scarb build

printf "${YELLOW}Pytest...\n"
pytest . -sv
if [ $? -eq 0 ]; then
    printf "${GREEN}Pytest succeed\n"
else
    printf "${RED}Pytest failed.\n"
    exit 1
fi


# Reset
printf "${COLOR_OFF}"

popd
