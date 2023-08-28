#!/bin/bash

#####################################################
# Version     : 1.0.0
# Script Name : scrap.sh
# Description : This script aims to search for vulnerabilities on websites. Please note that this script is for educational and experimental purposes only. Usage beyond these limits may violate the law. The author is not responsible for misuse or illegal use.
# License     : Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)
# Author      : @ghalangwh.official
# Date        : 08-08-2023
#####################################################


# Warna Terang
a="\e[90m"   #abu-abu
p="\e[97m"   #putih
m="\e[91m"   #merah
h="\e[92m"   #hijau
k="\e[93m"   #kuning
b="\e[94m"   #biru
u="\e[95m"   #ungu
c="\e[96m"   #cyan

# Warna Gelap
ag="\e[37m"  #abu-gelap
mg="\e[31m"  #merah-gelap
hg="\e[32m"  #hijau-gelap
kg="\e[33m"  #kuning-gelap
bg="\e[34m"  #biru-gelap
ug="\e[35m"  #ungu-gelap
cg="\e[36m"  #cyan-gelap



if [ -f user_agents.txt ] && [ -f list_page.txt ]; then
    tor_pid=$(ps aux | grep -v grep | grep "tor" | awk '{print $2}')

    curl -s ident.me &> /dev/null
    if [ $? -eq 0 ]; then
      if [ -z "$tor_pid" ]; then
        clear
        echo " [+] Please Running your tor"
        echo " [!] Tor is not running or you are not connected through Tor."
        exit 1
      else
# Daftar paket yang diperlukan
required_packages=("openssl" "nmap" "curl" "dig" "jq" "tor" "torsocks")
# Fungsi untuk memeriksa apakah paket sudah terinstal dan menginstal jika belum
function check_and_install_package() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "Paket $1 tidak ditemukan. Menginstal paket..."
        # Perintah instalasi paket berdasarkan jenis sistem operasi
	if [[ -n $(command -v pkg) ]]; then
            pkg install -y "$@" &> /dev/null
        elif [[ -n $(command -v apt-get) ]]; then
            sudo apt-get install -y "$@" &> /dev/null
        elif [[ -n $(command -v yum) ]]; then
            sudo yum install -y "$@" &> /dev/null
        else
            echo -e "Sistem operasi tidak didukung. Silakan instal paket dig,nmap,curl,jq,opensslsecara manual."
            exit 1
        fi
    fi
}

# Memeriksa dan menginstal setiap paket dalam daftar
for package in "${required_packages[@]}"; do
    check_and_install_package "$package"
done

clear

# Function to generate a random color code
generate_random_color() {
    echo $((RANDOM % 256))
}
# Function to print a colorful centered banner box                print_centered_banner_box() {
print_centered_banner_box() {
    local message="$1"
    local length=${#message}
    local terminal_width=$(tput cols)
    local border_char="="
    local padding_char=" "
    local num_colors=6  # Number of available colors
    local random_color1=$(generate_random_color)
    local random_color2=$(generate_random_color)

    # Calculate the width of the box
    local box_width=$((length + 4))

    # Calculate the left padding
    local left_padding=$(( (terminal_width - box_width) / 2 ))

    # Print the top border
    printf "\e[38;5;${random_color1}m%${left_padding}s" ""
    for ((i = 0; i < box_width; i++)); do
        printf "${border_char}"
    done
    printf "\e[0m\n"

    # Print the message line with alternating colors
    printf "\e[38;5;${random_color2}m%${left_padding}s${border_char}${padding_char}${message}${padding_char}${border_char}\e[0m\n"

    # Print the bottom border
    printf "\e[38;5;${random_color1}m%${left_padding}s" ""
    for ((i = 0; i < box_width; i++)); do
        printf "${border_char}"
    done
    printf "\e[0m\n"
}

# Usage example
print_centered_banner_box "Created By ghalangwh-official"

# get information from user
echo -e "\n ${p}[${m}+${p}] ${b}Information from me ${m}: ${hg}\n $(curl -s http://ip-api.com/json/$(torsocks curl -s ident.me) \n | jq | tr -d '{}",')"

# Menerima input dari pengguna
echo -n -e "\n ${p}[${mg}?${p}] ${kg}Masukkan ${mg}URL ${p}(${ag}http${m}/${a}https${p})${u}:${ug} ";read URL;

URL_REAL=$(echo ${URL} > .history_url_real.bak)
REAL=$(cat .history_url_real.bak)

# Menghapus kata-kata setelah / terakhir
URL=$(echo "$URL" | sed 's/\(https:\/\/[^\/]*\)\/.*/\1/')

# Mengubah URL menjadi huruf kecil
URL=$(echo "$URL" | tr '[:upper:]' '[:lower:]')

# Menghapus garis miring diakhir URL jika ada
URL=$(echo "$URL" | sed 's:/$::')

# Memeriksa apakah input dimulai dengan "http://" atau "https://"
if [[ $URL =~ ^(http|https):// ]]; then
    # Menampilkan response
    echo -e "\n ${P}[${mg}+${mg}${P}] ${kg}URL ${ug}: $REAL\n"
    RESPONSE=$(torsocks curl -sL -o /dev/null -w "%{http_code}" -A "$(shuf -n 1 user_agents.txt)" "${REAL}")
    if [[ $RESPONSE =~ ^(000|403|404|301|302)$ ]]; then
        echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${ug}${REAL} ${mg}- ${ug}Code: ${ag}[${hg}${RESPONSE}${ag}]"
        echo -e " ${p}[${a}!${p}] ${m}website/url Not found"
        exit
    elif [[ $RESPONSE == "200" ]]; then
        echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${ug}${REAL} ${mg}- ${ug}Code: ${ag}[${hg}${RESPONSE}${ag}]"
    else
        echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${ug}${REAL} ${mg}- ${ug}Code: ${ag}[${mg}${RESPONSE}${ag}]"
    fi
# Memeriksa apakah input dimulai dengan https/http
else
    echo -e " ${p}[${h}!${p}] ${ug}URL : ${k}${REAL} ${m}tidak valid"
    exit 1
fi

DOMAIN=$(echo "$URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
NOT_SUB=$(echo "$DOMAIN" | sed 's/^[^.]*\.//')
print_centered_banner_box "get the information on web"
echo -e "\n Title    : $(torsocks curl -sL $REAL | awk -F '</?title>' 'NF>2 {print $2; exit}')"
echo -e " Server   : $(torsocks curl -sLI $REAL | awk -F': ' '/^server:/ {print $2}')"

print_centered_banner_box "Contact"
echo -e " Contact  : \n$(torsocks curl -sL $REAL | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}|[[:alnum:]+\.\_\-]+@[[:alnum:]+\.\_\-]+\.[[:alpha:]]+' | sed 's/^[[:space:]]*//')"

print_centered_banner_box "Ekstrak link"
echo -e " Get_Link  : \n$(torsocks curl -sL $REAL | grep -o 'href="[^"]*"' | sed 's/href="//;s/"//g' | grep -Eo 'http[s]?://[^ ]+')"


# Nmap Info
   echo -e "\n"
   print_centered_banner_box "Nmap"
   echo -e " ${m}$(nmap ${DOMAIN})\n"

# Subdomain
   echo -e "\n"
   print_centered_banner_box "Subdomain"
   echo -e " ${c}$(nmap -sn --script hostmap-crtsh $NOT_SUB)\n"

# Dns Lookup
   print_centered_banner_box "Nslookup"
   echo -e "${hg}$(nslookup ${DOMAIN}) \n"

# Dig information
   print_centered_banner_box "Dig information"
   echo -e " ${bg}$(dig ${DOMAIN}) \n"

# Information with curl
   print_centered_banner_box "Header Website"
   echo -e "${kg}\n"
   curl -sLI -A "${UA}" "${URL}"

# Robots.txt finder
   print_centered_banner_box "Robots Finder"
ROBOTS_FIND=$(torsocks curl -s -o /dev/null -w "%{http_code}" -A "$(shuf -n 1 user_agents.txt)" "${URL}/robots.txt")
if [[ $ROBOTS_FIND == "200" ]]; then
    echo -e "\b" $(curl -s -A "$(shuf -n 1 user_agents.txt)" "${URL}/robots.txt") "\n"
else
    echo -e "\n [${mg}-${p}] ${kg}Robots.txt ${mg}Not Found \n"
fi

    print_centered_banner_box "Admin login Finder"

# Fungsi untuk memeriksa URL
check_url() {
    page="$1"
    FULL_URL="$URL/$page"
    RESPONSE=$(torsocks curl -sL -o /dev/null -w "%{http_code}" -A "$(shuf -n 1 user_agents.txt)" "${FULL_URL}")
    if [[ $RESPONSE == "200" ]]; then
        echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${bg}${FULL_URL} ${mg}- ${ug}Code: ${ag}[${hg}${RESPONSE}${ag}]"
        echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${bg}${FULL_URL} ${mg}- ${ug}Code: ${ag}[${hg}${RESPONSE}${ag}]" >> found.txt
    else
        echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${bg}${FULL_URL} ${mg}- ${ug}Code: ${ag}[${mg}${RESPONSE}${ag}]"
    fi
}

# URL dan jumlah maksimum thread

max_threads=5

# Baca setiap baris dari list_page.txt dan jalankan tugas dalam thread
while IFS= read -r page; do
    # Batasi jumlah thread yang sedang berjalan
    while [ $(jobs -r | wc -l) -ge $max_threads ]; do
        sleep 1
    done
    # Jalankan tugas dalam subshell (background process)
    (check_url "$page") &
done < list_page.txt

# Tunggu semua thread selesai
wait


echo -e "\n"
if [[ -f found.txt ]]; then
print_centered_banner_box "Admin login found"
cat found.txt
rm -rf found.txt;
else
print_centered_banner_box "Admin login not found"
echo -e " ${p}[${h}!${p}] ${m}Tidak Dapat Menemukan Admin Login Page, Silahkan Tambahkan page secara manual di page_list.txt"
exit
fi

fi

else
echo -e "[•] Please check your internet connection !"
fi

else
echo -e " [•] Please check your file connection !\n [•] Please install this is script on github"
fi
