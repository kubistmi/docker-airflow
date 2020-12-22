#!/bin/bash
# if [ -e "/reqs/r_packages.txt" ]; then
#     while read package; 
#     do 
#        $(command -v Rscript) -e "install.packages('"$package"')"; 
#     done < "/reqs/r_packages.txt"
# fi
if [ -e "/reqs/r_packages.txt" ]; then
    while IFS="=" read -r package version;
    do 
        $(command -v Rscript) -e "devtools::install_version('"$package"', version='"$version"')"; 
    done < "/reqs/r_packages.txt"
fi