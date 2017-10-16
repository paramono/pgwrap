#!/bin/bash

# run either as root or as the user that has a role of the same name in postgres
# for reference: https://stackoverflow.com/a/12236582/5618728

POSITIONAL=()
BECOME_USER=postgres
PG_USER=$BECOME_USER


confirm() {
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}


lastcmd_success() {
    result=$?
    if [ $result -ne 0 ]; then
        exit $result
    fi
}


pg_dump_command() {
    PG_DUMP_COMMAND="pg_dump -f ${DUMPFILE} -Ox ${DATABASE}"

    # if [ -n "$DB_OWNER"]; then
    #     PG_DUMP_COMMAND="${PG_DUMP_COMMAND} --role=${DB_OWNER}"
    # fi

    if [[ "$USER" == "root" ]]; then
        PG_DUMP_COMMAND="sudo -u ${BECOME_USER} bash -c '${PG_DUMP_COMMAND}'"
    fi

    if [ -n "$PG_USER" ]; then
        PG_DUMP_COMMAND="${PG_DUMP_COMMAND} -U ${PG_USER}"
    fi

    echo "Running: $PG_DUMP_COMMAND"
    eval $PG_DUMP_COMMAND
    lastcmd_success
}


pg_load_command() {
    PG_LOAD_COMMAND_1="dropdb ${DATABASE}"
    PG_LOAD_COMMAND_2="createdb ${DATABASE} -O ${DB_OWNER}"
    PG_LOAD_COMMAND_3="psql ${DATABASE} -f ${DUMPFILE}"

    # setting privileges
    # PG_LOAD_COMMAND_4="psql database -c 'GRANT ALL ON ALL TABLES IN SCHEMA public TO ${DB_OWNER};' &&"
    # PG_LOAD_COMMAND_5="psql database -c 'GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO ${DB_OWNER};' &&"
    # PG_LOAD_COMMAND_6="psql database -c 'GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO ${DB_OWNER};'"
    PG_LOAD_COMMAND_4="GRANT ALL ON ALL TABLES IN SCHEMA public TO ${DB_OWNER};"
    PG_LOAD_COMMAND_5="GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO ${DB_OWNER};"
    PG_LOAD_COMMAND_6="GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO ${DB_OWNER};"

    PG_LOAD_ARRAY_1=("$PG_LOAD_COMMAND_1" "$PG_LOAD_COMMAND_2" "$PG_LOAD_COMMAND_3")
    PG_LOAD_ARRAY_2=("$PG_LOAD_COMMAND_4" "$PG_LOAD_COMMAND_5" "$PG_LOAD_COMMAND_6")

    for i in "${PG_LOAD_ARRAY_1[@]}"
    do
        cmd=$i
        if [ -n "$PG_USER" ]; then
            cmd="$cmd -U $PG_USER"
        fi

        if [[ "$USER" == "root" ]]; then
            cmd="sudo -u $BECOME_USER bash -c \"$cmd\""
        fi 

        echo "Running: $cmd"
        eval $cmd
        lastcmd_success
    done

    for i in "${PG_LOAD_ARRAY_2[@]}"
    do
        cmd=$i
        if [ -n "$PG_USER" ]; then
            cmd="psql -d ${DATABASE} -U $PG_USER -c \"$cmd\""
        else
            cmd="psql -d ${DATABASE} -c \"$cmd\""
        fi

        if [[ "$USER" == "root" ]]; then
            cmd="sudo -u $BECOME_USER bash -c '$cmd'"
        fi 
        echo "Running: $cmd"
        eval $cmd
        lastcmd_success
    done
}


# Assigning cmd arguments to variables
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        -d|--database)
        DATABASE="$2"
        shift # past argument
        shift # past value
        ;;
        -f|--file)
        DUMPFILE="$2"
        shift # past argument
        shift # past value
        ;;
        -o|--owner)
        DB_OWNER="$2"
        shift # past argument
        shift # past value
        ;;
        -u|--user|--become-user)
        BECOME_USER="$2"
        shift # past argument
        shift # past value
        ;;
        --no-input)
        NOINPUT=yes
        shift # past argument
        ;;
        --default)
        DEFAULT=YES
        shift # past argument
        ;;
        *)    # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        ;;
esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters
COMMAND="$1"


# main
PG_USER=$BECOME_USER
if [[ $COMMAND == "dump" ]]; then
    : ${DUMPFILE?"Need to set DUMPFILE with -f|--file"}
    : ${DATABASE?"Need to set DATABASE with -d|--db"}
    echo "Dumping database ${DATABASE} to file ${DUMPFILE}..."

    # pg_dump -f ${DUMPFILE} -Ox ${DATABASE}
    pg_dump_command
elif [[ $COMMAND == "load" ]]; then
    : ${DUMPFILE?"Need to set DUMPFILE with -f|--file"}
    : ${DATABASE?"Need to set DATABASE with -d|--db"}
    : ${DB_OWNER?"Need to set DB_OWNER with -o|--owner"}

    if [ -z $NOINPUT ]; then
        WARNING_TEXT="This command will destroy, then recreate the database "
        WARNING_TEXT+="'${DATABASE}' from dumpfile '${DUMPFILE}' and grant "
        WARNING_TEXT+="all permissions to postgres role '${DB_OWNER}'"
        echo "$WARNING_TEXT"

        confirm "Do you want to proceed? [y/N]"
        answer=$?
        echo -e ""  # empty line

        if [ "$answer" -eq "1" ]; then
            echo "Aborting"
            exit 1
        fi
    fi

    LOADING_TEXT="Loading dump file '${DUMPFILE}' to database '${DATABASE}' "
    LOADING_TEXT+="and granting privileges to owner '${DB_OWNER}'..."
    echo $LOADING_TEXT

    pg_load_command
else
    echo "'$COMMAND' command not supported. Try 'dump' or 'load' instead"
    exit 1
fi
