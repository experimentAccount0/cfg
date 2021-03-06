#!/usr/bin/env bash

set -e

tarcmd() {
    opts=(cf - --numeric-owner --ignore-failed-read -C / -l)
    set +e; tar "${opts[@]}" "$@"; rv=$?; set -e
    [[ "$rv" -eq 0 ]] || [[ "$rv" -eq 1 ]]
}

common_findopts=(-type f -a -print0 -or -type l -print0)
specialfiles=(
    boot
    lib/modules var/lib/dkms
    vmlinuz initrd.img
    etc/{blkid.,fs}tab)

all_pkgs() {
    dpkg-query -W -f '${Package}:${Architecture}\n'
}

declare -A SYSTEM_FILES

collect_systemfiles() {
    local all_pkgs=($(all_pkgs))

    while read -r; do
        if ! [[ -z "$REPLY" ]]; then
            SYSTEM_FILES[$REPLY]=1
        fi
    done < <(dpkg-query -L "${all_pkgs[@]}")
}

not_systemfile() {
    [[ -z "${SYSTEM_FILES[$1]}" ]]
}

find_systemfiles() {
    local excludes=(
        "${specialfiles[@]}"
        dev proc run sys tmp
        home place mnt
        usr/share/{mime,snmp}
        var/{cache,log,local,spool,tmp}
        var/lib/{apt{,itude},dpkg}
        {data/,var/lib/}vz/{dump,lock,private,root}
        var/lib/{cron-apt,gems,mysql,nagios3/spool,puppet})
    local exts=(d o pyc)
    local cmd=(find /) start=1
    for path in "${excludes[@]}"; do
        [[ -z "$start" ]] && cmd+=(-o) || start=
        cmd+=(-path "/$path" -prune)
    done
    for ext in "${exts[@]}"; do cmd+=(-o -name "*.$ext"); done
    cmd+=(-o "${common_findopts[@]}")
    "${cmd[@]}"
}

find_userfiles() {
    find /home -mount "${common_findopts[@]}"
}

conffiles() {
    all_pkgs=($(all_pkgs))
    declare -A conffiles
    while read -r; do
        if ! [[ -z "$REPLY" ]]; then
            spec="${REPLY# *}"
            file="${spec% *}"
            sum="${spec##* }"
            if [[ -r "$file" ]]; then
                conffiles[$file]=$sum
            fi
        fi
    done < <(dpkg-query -f '${Conffiles}\n' -W "${all_pkgs[@]}")

    tarcmd -T <(while read -r; do
        local sum="${REPLY%%  *}" file="${REPLY#*  }"
        if [[ "${conffiles[$file]}" != "$sum" ]]; then
            echo "${file:1}"
        fi
    done < <(md5sum "${!conffiles[@]}"))
}

find_specialfiles() {
    files=()
    for file in "${specialfiles[@]}"; do
        [[ -e "/$file" ]] && files+=("/$file")
    done
    find "${files[@]}" "${common_findopts[@]}"
}

diff_backup() {
    local findcmd=$1 filtercmd=$2

    declare -A sums
    while read -r -d ''; do
        sum=${REPLY%% *}
        file="/${REPLY#* }"
        sums[$file]=$sum
    done

    tarcmd --null -T <(
        hardlinks_to_check=()
        symlinks_to_check=()
        files_to_check=()
        while read -r -d ''; do
            if "$filtercmd" "$REPLY"; then
                if [[ -z "${sums[$REPLY]}" ]]; then
                    echo -en "${REPLY:1}\0"
                else
                    if [[ "$(stat -c "%h" "$REPLY")" -gt 1 ]]; then
                        sum=${sums[$REPLY]}
                        if [[ "${sum:0:1}" == 'H' ]]; then
                            hardlinks_to_check+=("$REPLY")
                        fi
                    # symlinks first, as -f gives OK if the target exists
                    elif [[ -L "$REPLY" ]]; then
                        symlinks_to_check+=("$REPLY")
                    elif [[ -f "$REPLY" ]]; then
                        files_to_check+=("$REPLY")
                    else
                        echo "$REPLY: file type is not supported" >&2
                    fi
                fi
            fi
        done < <("$findcmd")

        if [[ "${#hardlinks_to_check[@]}" -gt 0 ]]; then
            for link in "${hardlinks_to_check[@]}"; do
                sum=${sums[$link]}
                target=$(echo -n "${sum:1}" | base64 -d)
                if [[ "$(ls -i "$link" | cut -f1 -d' ')" -ne \
                      "$(ls -i "/$target" | cut -f1 -d' ')" ]]; then
                    echo -en "${link:1}\0"
                fi
            done
        fi

        if [[ "${#symlinks_to_check[@]}" -gt 0 ]]; then
            for link in "${symlinks_to_check[@]}"; do
                sum=$(readlink -n "$link" | base64)
                if [[ "${sums[$link]}" != "L$sum" ]]; then
                    echo -en "${link:1}\0"
                fi
            done
        fi

        if [[ "${#files_to_check[@]}" -gt 0 ]]; then
            for file in "${files_to_check[@]}"; do
                echo -en "$file\0"
            done | xargs --null md5sum | while read -r; do
                start=${REPLY:0:1}
                filename=${REPLY#*  }
                if [[ "$start" == '\' ]]; then
                    filename=$(echo -en "$filename")
                    sum=${REPLY:1:32}
                else
                    sum=${REPLY:0:32}
                fi
                if [[ "${sums[$filename]}" != "F$sum" ]]; then
                    echo -en "${filename:1}\0"
                fi
            done
        fi
    )
}

backup_mysql() {
    mysqldump \
        --defaults-extra-file=/etc/mysql/debian.cnf \
        --lock-tables \
        --all-databases \
        --events --ignore-table=mysql.event \
        --default-character-set=utf8 | \
    gzip
}

case "$1" in
    pkgs)       apt-mark showmanual ;;
    conf)       conffiles ;;
    sys)        collect_systemfiles; diff_backup find_systemfiles not_systemfile ;;
    user)       diff_backup find_userfiles true ;;
    special)    diff_backup find_specialfiles true ;;
    mysql)      backup_mysql ;;
    postgresql) cd / && su postgres -c 'pg_dumpall | gzip' ;;
    *)          exit 1 ;;
esac
