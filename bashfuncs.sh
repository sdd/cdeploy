#!/bin/bash
##################################################################
# USEFUL BASH UTILITY FUNCTIONS ##################################
##################################################################

#======================================================
# contains: test if bash array contans value
# credit: http://stackoverflow.com/questions/3685970/bash-check-if-an-array-contains-a-value
#
# usage:
#
# A=("one" "two" "three four")
# if [ $(contains "${A[@]}" "one") == "y" ]; then
#     echo "contains one"
# fi
#======================================================
function contains() {
    local n=$#
    local value=${!n}
    for ((i=1;i < $#;i++)) {
        if [ "${!i}" == "${value}" ]; then
            echo "y"
            return 0
        fi
    }
    echo "n"
    return 1
}
