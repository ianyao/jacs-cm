#!/bin/bash
#
# Management script for Docker containers
#

# Exit on error
set -e

# Constants
DOCKER="docker"
DOCKER_COMPOSE="docker-compose"
REGISTRY_SERVER="registry.int.janelia.org"
NAMESPACE="scsw"

if [ -z "${SSH_PRIVATE_KEY}" ]; then
    if [[ -e ~/.ssh/id_dsa ]]; then
	SSH_PRIVATE_KEY="$(cat ~/.ssh/id_dsa)"
    elif [[ -e ~/.ssh/id_rsa ]]; then
	SSH_PRIVATE_KEY="$(cat ~/.ssh/id_rsa)"
    fi
fi

DIR=$(cd "$(dirname "$0")"; pwd)

if [[ -z "$SSH_PRIVATE_KEY" ]]; then
    echo "You need to set up password-less SSH for Github before using this script"
    exit 1
fi

if [[ -z $DIR/.env ]]; then
    echo "You need to configure your .env file before using this script. Get started by copying the template:"
    echo '  cp .env.template .env'
    exit 1
fi

if [[ -z "$DOCKER_USER" ]]; then
    UNAME=jacs
    GNAME=jacsdata
    MYUID=$(id -u $UNAME)
    MYGID=`cut -d: -f3 < <(getent group $GNAME)`
    DOCKER_USER=$MYUID:$MYGID
fi

if [[ "$1" == "init-filesystem" ]]; then
    $DIR/setup/init-filesystem.sh $DOCKER_USER
    echo "Filesystem initialized"
    exit 0
fi

if [[ "$1" == "init-databases" ]]; then
    sudo $DOCKER run --rm --env-file .env --network jacscm_jacs-net registry.int.janelia.org/scsw/jacs-init:latest
    echo "Databases initialized"
    exit 0
fi

if [[ "$#" -lt 2 ]]; then
    echo "Usage: `basename $0` [build|run|shell|push|up|down] [tool1] [tool2] .. [tooln]"
    echo "       You can combine multiple commands with a plus, e.g. build+push"
    echo "       For the up/down commands, the argument must be a tier name like 'dev' or 'prod'"
    exit 1
fi

COMMANDS=$1
CMDARR=(${COMMANDS//+/ })
shift 1 # remove command parameter from args

for COMMAND in "${CMDARR[@]}"
do
    #echo "Executing $COMMAND command on these targets: $@"

    if [[ "$COMMAND" == "build" ]]; then

        echo "Will build these images: $@"

        for NAME in "$@"
        do
            NAME=${NAME%/}
            if [[ -e $NAME/VERSION ]]; then
                VERSION=`cat $NAME/VERSION`
                CNAME=${REGISTRY_SERVER}/${NAMESPACE}/${NAME}
                VNAME=$CNAME:${VERSION}
                LNAME=$CNAME:latest
                APP_TAG="${APP_TAG:-master}"
                echo "---------------------------------------------------------------------------------"
                echo " Building image for $NAME"
                echo " sudo $DOCKER build --no-cache --build-arg SSH_PRIVATE_KEY=<hidden> --build-arg APP_TAG=$APP_TAG -t $VNAME -t $LNAME $NAME"
                echo "---------------------------------------------------------------------------------"
                sudo $DOCKER build --no-cache --build-arg SSH_PRIVATE_KEY="$SSH_PRIVATE_KEY" --build-arg APP_TAG="$APP_TAG" -t $VNAME -t $LNAME $NAME
            else
                echo "No $NAME/VERSION found"
            fi
        done

    elif [[ "$COMMAND" == "run" ]]; then

        NAME=${1%/}
        if [[ -e $NAME/VERSION ]]; then
            VERSION=`cat $NAME/VERSION`
            CNAME=${REGISTRY_SERVER}/${NAMESPACE}/${NAME}
            VNAME=$CNAME:${VERSION}
            echo "sudo $DOCKER run -it -u $DOCKER_USER --rm $VNAME"
            sudo $DOCKER run -it -u $DOCKER_USER --rm $VNAME
        else
            echo "No $NAME/VERSION found"
        fi

    elif [[ "$COMMAND" == "shell" ]]; then

        NAME=${1%/}
        if [[ -e $NAME/VERSION ]]; then
            VERSION=`cat $NAME/VERSION`
            CNAME=${REGISTRY_SERVER}/${NAMESPACE}/${NAME}
            VNAME=$CNAME:${VERSION}
            echo "sudo $DOCKER run -it -u $DOCKER_USER $VNAME /bin/bash"
            sudo $DOCKER run -it $VNAME /bin/bash
        else
            echo "No $NAME/VERSION found"
        fi

    elif [[ "$COMMAND" == "push" ]]; then

        echo "Will push $@ to $REGISTRY_SERVER"

        for NAME in "$@"
        do
            NAME=${NAME%/}
            if [[ -e $NAME/VERSION ]]; then
                VERSION=`cat $NAME/VERSION`
                CNAME=${REGISTRY_SERVER}/${NAMESPACE}/${NAME}
                VNAME=$CNAME:${VERSION}
                LNAME=$CNAME:latest
                echo "---------------------------------------------------------------------------------"
                echo " Pushing image for $VNAME"
                echo " sudo $DOCKER push $VNAME"
                echo "---------------------------------------------------------------------------------"
                sudo $DOCKER push $VNAME
                echo "---------------------------------------------------------------------------------"
                echo " Pushing image for $LNAME"
                echo " sudo $DOCKER push $LNAME"
                echo "---------------------------------------------------------------------------------"
                sudo $DOCKER push $LNAME
            else
                echo "No $NAME/VERSION found"
            fi
        done

    else
        # any other command is passed to docker-compose
        TIER=$1
        shift 1 # remove tier
        if [[ $1 == "--dbonly" ]]; then
            shift 1 # remove dbonly flag
            YML="-f docker-compose-db.yml"
            if [ -n "${TIER}" ]; then
	        if [[ -e "docker-compose.${TIER}-db.yml" ]]; then
		    YML="$YML -f docker-compose.${TIER}-db.yml"
		fi
            fi
        else
            YML="-f docker-compose-db.yml -f docker-compose-app.yml"
            if [ -n "${TIER}" ]; then
	        if [[ -e "docker-compose.${TIER}-db.yml" ]]; then
		    YML="$YML -f docker-compose.${TIER}-db.yml"
		fi
	        if [[ -e "docker-compose.${TIER}-app.yml" ]]; then
		    YML="$YML -f docker-compose.${TIER}-app.yml"
		fi
	        if [[ -e "docker-compose.${TIER}.yml" ]]; then
		    YML="$YML -f docker-compose.${TIER}.yml"
		fi
            fi
        fi
        echo "Bringing $COMMAND $TIER tier"
        echo "sudo SSH_PRIVATE_KEY=<hidden> DOCKER_USER="$DOCKER_USER" $DOCKER_COMPOSE $YML $COMMAND $@"
        sudo SSH_PRIVATE_KEY="$SSH_PRIVATE_KEY" DOCKER_USER="$DOCKER_USER" $DOCKER_COMPOSE $YML $COMMAND $@

    fi

done
