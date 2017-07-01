#!/bin/bash

# Simulator 1C
#
# Copyright 2014 iMega ltd (email: info@imega.ru)
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
#
# USAGE
#
# $ simulator1c.sh http://localhost "1C+Enterprise/8.3" \
#   "9915e49a-4de1-41aa-9d7d-c9a687ec048d:8c279a62-88de-4d86-9b65-527c81ae767a" \
#   fixtures/2.04
#

URL=$1
AGENT=$2
AUTH=$3
DIR=$4

function auth
{
    res=`query "catalog" "checkauth"`
    if [[ $res == 'failure' ]]; then
        echo 'Error Auth'
        exit 1
    fi
    explode=($res)

    echo ${explode[2]}
}

function compressZip
{
    echo Compress files to zip
    zip -1j $tmp/simulator1c.zip $DIR/*
}

# Import file in db
#
# @param string $1 filename
# @param string $2 token
function import
{
    res=`curl -sS --user $AUTH -H 'Cookie: token='$2 --user-agent $AGENT "$URL/?type=catalog&mode=import&filename=$1"`
    if [[ $res == 'failure' ]]; then
        echo 'Error Auth'
        exit 1
    fi

    IFS='\n' read -ra status <<< "$res"

    while [[ $status == 'progress' ]]; do
        sleep 2
        res=`curl -sS --user $AUTH -H 'Cookie: token='$2 --user-agent $AGENT "$URL/?type=catalog&mode=import&filename=$1"`
        IFS='\n' read -ra status <<< "$res"
        printf "."
    done
    echo $status
}

#
# param $1 token
#
function init
{
    res=`query "catalog" "init" $1`
    if [[ $res == 'failure' ]]; then
        echo 'Error Auth'
        exit 1
    fi

    for line in $res; do
        IFS='=' read -ra PARAM <<< "$line"
        if [[ ${PARAM[0]} == 'zip' ]]; then
            ZIP=${PARAM[1]}
        fi
        if [[ ${PARAM[0]} == 'file_limit' ]]; then
            LIMIT=${PARAM[1]}
        else
            LIMIT=-1
        fi
    done

    if [[ $ZIP == 'yes' ]]; then
        compressZip
    else
        cp $DIR/* $tmp/
    fi

    for file in $tmp/*; do
        if [[ -f $file ]]; then
            if [ $LIMIT -gt 0 ]; then
                file_size=$(stat -c%s "$file")
                filename=$(basename $file)
                DEST="$tmp/to_send/$filename"
                mkdir -p $DEST
                if [ $file_size -gt $LIMIT ]; then
                    splitFile $file $DEST $LIMIT
                else
                    mv $file $DEST/
                fi
            fi
        fi
    done
}

#
# param $3 token
#
function query
{
    curl -sS --user $AUTH -H 'Cookie: token='$3 --user-agent $AGENT "$URL/?type=$1&mode=$2"
}

# Send file
#
# @param string $1 a file
# @param string $2 filename
# param $3 token
function sendfile
{
    for file in $1/*; do
        if [[ -f $file ]]; then
            echo $file
            curl -sSX POST --user $AUTH -H 'Cookie: token='$3 --user-agent $AGENT --data-binary @$file "$URL/?type=catalog&mode=file&filename=$2" > /dev/null
        fi
    done
}

# sendfiles
#
# param $1 token
function sendfiles
{
    for folder in $tmp/to_send/*; do
        if [[ -d $folder ]]; then
            name=$(basename $folder)
            sendfile $folder $name $1
        fi
    done
}

# Split file
#
# @param string $1 full filename
# @param strint $2 path destination split of file
# @param int    $3 bytes in length
function splitFile
{
    echo Split files
    PWD=`pwd`
    cd $2
    split -b $3 $1
    cd $PWD
}

echo "iMegaTeleport Simulator 1C"

tmp="/tmp/simulator1c"
mkdir -p $tmp

token=$(auth)
init $token
sendfiles $token
import "import.xml" $token
import "offers.xml" $token

rm -rf $tmp
echo -e "Done!"

exit $?
