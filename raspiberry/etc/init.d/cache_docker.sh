#!/bin/bash

BASE_DIR=/docker
CACHE_DIR=/cache/docker

function update_config(){
    ROOT_DIR=$1

    if [ $(systemctl is-active docker) = "active" ]
    then
        systemctl stop docker
    fi

    # check is /etc/docker/daemon.json need to update
    same_flag=0
    if [ -f /etc/docker/daemon.json ]
    then
        rslt=$(cat /etc/docker/daemon.json | grep "data-root" |sed "s/.*data-root.*: *\"\(.*\)\".*/\1/g")
        if [ $rslt = $ROOT_DIR ]
        then
    	    same_flag=1
        fi
    fi
    
    # update docker root dir if /etc/docker/daemon.json is not exists
    if [ $same_flag -eq 0 ]
    then 
        mount -o remount,rw,noatime,nodiratime /dev/sda2 /
    
        if [ ! -f /etc/docker/daemon.json ]
        then
            cat <<EOT > /etc/docker/daemon.json
{ 
   "data-root": "$ROOT_DIR" 
}
EOT
        else
            sed -i "s,\"data-root\": *.*,\"data-root\": \"$ROOT_DIR\",g"  /etc/docker/daemon.json
        fi
        mount -o remount,ro /dev/sda2 /
    fi
}


function get_image_base_layer(){
    if [ $(systemctl is-active docker) != "active" ]
    then
        systemctl start docker
    fi

    image_layers_id=""
    for image_id in $(docker images --format '{{.ID}}' |xargs)
    do
	for layer_id in $(docker inspect $image_id |grep LowerDir |sed 's#\s*"LowerDir": "\(.*\)",#\1#g' |sed 's#/diff# #g' |sed 's#:##g')
	do
	    layer_id=$(echo $layer_id |awk -F '/' '{print $(NF)}')
	    image_layers_id="$image_layers_id $layer_id"
	done
    done
    echo $image_layers_id
}


function cleanup_container(){
    if [ $(systemctl is-active docker) != "active" ]
    then
        systemctl start docker
    fi

    for container_id in $(docker ps --format '{{.ID}}')
    do
	docker stop $container_id
	docker rm $container_id
    done
    
    for container_id in $(docker ps -a --format '{{.ID}}')
    do
	docker rm $container_id
    done
}


function deploy_cache_version(){
    if [ $(systemctl is-active docker) = "active" ]
    then
        systemctl stop docker
    fi

    # make sure a clean cache dir is exists
    mkdir -p $CACHE_DIR && rm -rf $CACHE_DIR/*

    cleanup_container
    
    image_layers_id=$(cat $BASE_DIR/base_layers_list.txt)
    
    # copy all files except for the images layers
    for layer_id in $(echo $image_layers_id)
    do
        PARAMS="$PARAMS --exclude=overlay2/$layer_id"
    done
    rsync -ar --delete $PARAMS $BASE_DIR/ $CACHE_DIR/
    
    
    # link all the docker images layers to cache dir
    for layer_id in $image_layers_id
    do
        ln -s $BASE_DIR/overlay2/$layer_id $CACHE_DIR/overlay2/$layer_id
    done

    # It's strange, we must to stop and start again to see the docker images.
    # A sleep is also needed before start. 
    # or, there will be a error: The unit docker.service has entered the 'failed' state with result 'start-limit-hit
    # looks like the firewll or the fucking systemd was set a limit in somewhere.
    systemctl start docker
    sleep 3
    systemctl stop docker
    systemctl start docker
}


function check_baselayers_list(){
    # get images' layers list
    if [ ! -f $BASE_DIR/base_layers_list.txt ]
    then
	echo $BASE_DIR/base_layers_list.txt is not found.
	exit 1
    fi
}


function set_baselayers_list(){
    mount -o remount,rw,noatime,nodiratime /dev/sda2 /

    if [ $(systemctl is-active docker) != "active" ]
    then
        systemctl start docker
    fi
    new_base_layers=$(get_image_base_layer)
    if [ -f $BASE_DIR/base_layers_list.txt ]
    then
        old_base_layers=$(cat $BASE_DIR/base_layers_list.txt |xargs)
        if [ "$new_base_layers" = "$old_base_layers" ]
        then
	    return
        fi
    fi
    echo $new_base_layers > $BASE_DIR/base_layers_list.txt

    mount -o remount,ro /dev/sda2 /
}




case "$1" in

    start|"")
	check_baselayers_list
	update_config $CACHE_DIR
	deploy_cache_version
	exit $?
	;;

    restart|"")
	check_baselayers_list
	deploy_cache_version
	exit $?
	;;

    reload)
	update_config $BASE_DIR
	set_baselayers_list
	update_config $CACHE_DIR
	deploy_cache_version
	exit $?
	;;

    stop)
    	if [ $(systemctl is-active docker) = "active" ]
    	then
    	    systemctl stop docker
    	fi
	rm -rf $CACHE_DIR/*
	exit $?
	;;

    restore)
	update_config $BASE_DIR
	rm -rf $CACHE_DIR/*
        mount -o remount,rw,noatime,nodiratime /dev/sda2 /
	systemctl start docker

	exit $?
	;;

    *)
	echo f
	exit 3
	;;

esac