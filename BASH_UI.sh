#!/bin/bash
#                                                                                   #
# This is an interactive front-end for the slice-to-volume C++ program.             #
#                                                                                   #
# This code was designed for a specific task. The majority of it, however, should   #
# be able to be adapted for most PBS-script based applications.                     #
#                                                                                   #
#                                                                                   #
# @NOTE                                                                             #
#    Be sure to set the variable 'PROGRAM' to the absolute path of the executable   #
#####################################################################################

set -e

# Description: Given a relative path, this function return the physical path of its parent directory.
#   i.e.
#       phy_path ~/c/d` would find the physical path of directory '~/c/' ('/a/b/c/') and return:
#           '/a/b/c/d'
#
#   If no path of the parent directory does not exist, no value is returned.
phy_path() {
    if [[ "$1" ]]; then
        ARG="$@"
        if [[ "${ARG:0:2}" == "~/" ]]; then
            ARG="$HOME/${ARG:2}"
        fi

        if [[ -d "$(dirname "$ARG/")" ]]; then
            echo "$( cd "$(dirname "$ARG")" ; pwd -P )/$(basename "$ARG")";
        fi
    fi
}


# BEGIN Variables

logo='
 /$$   /$$                    /$$$$$$  /$$ /$$
| $$  | $$                   /$$__  $$| $$|__/
| $$  | $$ /$$$$$$$         | $$  \__/| $$ /$$  /$$$$$$$  /$$$$$$   /$$$$$$
| $$  | $$| $$__  $$ /$$$$$$|  $$$$$$ | $$| $$ /$$_____/ /$$__  $$ /$$__  $$
| $$  | $$| $$  \ $$|______/ \____  $$| $$| $$| $$      | $$$$$$$$| $$  \__/
| $$  | $$| $$  | $$         /$$  \ $$| $$| $$| $$      | $$_____/| $$
|  $$$$$$/| $$  | $$        |  $$$$$$/| $$| $$|  $$$$$$$|  $$$$$$$| $$
 \______/ |__/  |__/         \______/ |__/|__/ \_______/ \_______/|__/
'

PROGRAM='<Path to executable>'
DRYRUN=false;
QUIET=false;
OPTIONS=""


if [ "$1" = "-h"  -o "$1" = "--help" ]     # Request help.
then                                       # Use a "cat script" . . .
  cat <<DOCUMENTATIONXX
$logo
Usage:
    $(basename "$0") [option]...
Submit a registration task to the cluster.

Options:
-d              Dry-run; do not submit the job to the cluster, just show what would happen.
-r              Do not perform any registration between slices
-q              Quiet; use defaults when available
-g <decimal>    Specify an alternative gradient smoothing SD (default: 4.0)
-c <integer>    Specify an alternative number of iterations  (default: 50)
-i <directory>  Specify the input directory
-o <directory>  Specify the output directory
-h | --help     Display this message

DOCUMENTATIONXX
exit $DOC_REQUEST
fi

while getopts ":drqg:c:i:o:" opt
do
    case $opt in
    d)  DRYRUN=true;;
    r)  OPTIONS="$OPTIONS -R";;
    q)  QUIET=true;;
    g)  OPTIONS="$OPTIONS -S $OPTARG";;
    c)  OPTIONS="$OPTIONS -I $OPTARG";;
    i)  INPUT="$OPTARG";;
    o)  OUTPUT="$OPTARG";;
    *)  echo "Un-imlemented option chosen"
        echo "Try '$0 -h' for usage details."
        exit;;
    esac
done

# END Variables


clear;
echo "$logo"
if [[ "$DRYRUN" = true ]]; then
    COL_RED="$(tput setaf 1)$(tput bold)"
    COL_NORM="$(tput setaf 9)$(tput sgr0)"
    echo "${COL_RED}NOTE: Dry-Run only. Job will not be submitted.${COL_NORM}"
    # echo "${COL_NORM}";
fi

if [[ -z "$INPUT" ]]; then
    read -e -p "What is the path for the directory of input files? " INPUT
    echo;
fi

# If 'INPUT' is a relative path, convert it to a physical one
INPUT="$(phy_path "$INPUT")"

# `phy_path` only checks a path's parent directory, so the last value in path needs to be varified as a folder
if ( [[ -z "$INPUT" ]] || ! [[ -d "$INPUT" ]] ); then
    echo -e "ERROR!!!\nThe path:";
    echo -e "\t'$INPUT'";
    echo -e "does not exist.\nPlease ensure that you have entered it correctly. ";
    echo -e "\nExiting...";
    exit;
fi

if [[ -z "$OUTPUT" ]]; then
    read -e -p "What is the path for the output directory? " OUTPUT
    echo;
fi

# If 'OUTPUT' is a relative path, convert it to a physical one
OUTPUT="$(phy_path "$OUTPUT")"

if [[ -z "$OUTPUT" ]]; then
    echo -e "ERROR!!!\nThe path:";
    echo -e "\t'$OUTPUT'";
    echo -e "does not exist.\nPlease ensure that you have entered it correctly. ";
    echo -e "\nExiting...";
    exit;
# If the 'OUTPUT' path is a directory or non-existsant, that is fine, but it cannot be a file.
elif [[ -f "$OUTPUT" ]]; then
    echo -e "ERROR!!!\nThe path:";
    echo -e "\t'$OUTPUT'";
    echo -e "points to a file.\nPlease re-examine your parameters. ";
    echo -e "\nExiting...";
    exit;
fi

DIRSIZE=$(du -S "$INPUT" | cut -f 1)

# Get memory requirements in kB
MEM=$(expr $DIRSIZE \* 3)

# Convert memory requirement from bytes to MB / GB / etc
MEM=$(echo $MEM | awk '
    function human(x) {
        if (x<1000) {return x} else {x/=1024}
        s="MGTEPYZ";
        while (x>=1000 && length(s)>1)
            {x/=1024; s=substr(s,2)}
        return int(x+0.5) substr(s,1,1)
    }
    {sub(/^[0-9]+/, human($1)); print}'
)

# Count the number of files in the folder
NF=$(ls -fq "$INPUT" | wc -l)

# Provide a generous estimate for the required computation time
# NOTES:
#   This may need to be adjusted.
#   User input may ultimately prove the preferable way to go
if [[ $NF -gt 99 ]]; then
    HRS=$(printf %02d $(expr $NF / 100))
    CPUT="${HRS}:00:00"
else
    CPUT="01:00:00"
fi

NAME="$(basename "$INPUT")"

PBS="#!/bin/bash
#PBS -N S2V_$NAME
#PBS -l nodes=1:ppn=16,mem=${MEM},cput=$CPUT,walltime=$CPUT"

if [[ "$DRYRUN" = false ]] && ! [[ -d "$OUTPUT" ]]; then
    mkdir "$OUTPUT";
fi

LOGFILE="$OUTPUT/output.log"

if [[ "$QUIET" = false ]]; then
    echo "What file would you like to use to observe the output status of this job?"
    echo -e "default is:\n\t$LOGFILE"
    read -e USRLOG

    ERR="echo -e \"\nERROR! ! ! \nThe path:\n\t'\${USRLOG}'\nDoes not point to a valid location.\nUsing the default location...\n\"";


    # If the user specifies an alternative logfile location, validate it.
    if [[ "$(phy_path "$USRLOG")" ]]; then
        USRLOG="$(phy_path "$USRLOG")";

        # If the user specifies a directory rather than a file, attempt to use it.
        if [[ -d "$USRLOG" ]]; then
            USRLOG="$USRLOG/run-log.log"
            if [[ -d "$USRLOG" ]]; then
                eval "$ERR"
            else
                LOGFILE="$USRLOG"
            fi
        else
            LOGFILE="$USRLOG"
        fi
    elif [[ "$USRLOG" ]]; then
    # If the user entered a location, but the physical path couldn't be found, fallback
        eval "$ERR"
    fi

    echo "What email address should be used to contact you for status updates?"
    echo "(or enter 'none' to opt out)"
    read -r EMAIL

    if [[ "$EMAIL" ]] && ! [[ "$EMAIL" =~ ^([nN][oO][nN][eE]) ]]; then
        PBS="${PBS}
    #PBS -m ae -M $EMAIL"
    fi
fi

PBS="${PBS}

'$PROGRAM' '$INPUT/' '$OUTPUT/' $OPTIONS &> '$LOGFILE'
"

echo -e "\nSubmitting task to cluster...\n"

if [[ "$DRYRUN" = false ]]; then
    # Feed PBS script into `qsub` as a here-string:
    ID=$(qsub /dev/stdin <<< "$PBS")
else
    COL_BG="$(tput bold)"
    COL_BG_NORM="$(tput sgr0)"
    echo "${COL_BG}## BEGIN PBS SCRIPT"
    echo "$PBS"
    echo "## END PBS SCRIPT${COL_BG_NORM}"
    echo
    ID="<RUN ID>"
fi
# Extract proccess ID from return text:
ID=$(echo $ID | cut -d '.' -f 1)

echo -e "${COL_NORM}Done!\n"
echo "You can check the status of your task though the following commands:"
echo "-- View the task's position in the que:"
echo -e "\tqstat $ID"
echo "-- View the status of the task:"
echo -e "\tcheckjob $ID"
echo "-- Abort the task early:"
echo -e "\tcanceljob $ID"
echo "-- Watch the output of the task:"
echo -e "\ttail -f '$LOGFILE'\n"
exit
