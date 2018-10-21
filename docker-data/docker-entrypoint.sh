#!/bin/sh

if [ "$1" = 'redis-cluster' ]; then
    # Allow passing in cluster IP by argument or environmental variable
    IP="${2:-$IP}"

    max_port=6386
    if [ "$CLUSTER_ONLY" = "true" ]; then
      max_port=6384
    fi

    for port in `seq 6379 $max_port`; do
      mkdir -p /redis-conf/${port}
      mkdir -p /redis-data/${port}

      if [ -e /redis-data/${port}/nodes.conf ]; then
        rm /redis-data/${port}/nodes.conf
      fi

      if [ "$port" -lt "6385" ]; then
        PORT=${port} envsubst < /redis-conf/redis-cluster.tmpl > /redis-conf/${port}/redis.conf
      else
        PORT=${port} envsubst < /redis-conf/redis.tmpl > /redis-conf/${port}/redis.conf
      fi

      if [ "$port" -lt "6382" ]; then
        if [ "$SENTINEL" = "true" ]; then
          PORT=${port} SENTINEL_PORT=$((port - 2000)) envsubst < /redis-conf/sentinel.tmpl > /redis-conf/sentinel-${port}.conf
          cat /redis-conf/sentinel-${port}.conf
        fi
      fi

    done

    bash /generate-supervisor-conf.sh $max_port > /etc/supervisor/supervisord.conf

    supervisord -c /etc/supervisor/supervisord.conf
    sleep 3

    if [ -z "$IP" ]; then # If IP is unset then discover it
        IP=$(hostname -I)
    fi
    IP=$(echo ${IP}) # trim whitespaces

    echo "yes" | ruby /redis/src/redis-trib.rb create --replicas 1 ${IP}:6379 ${IP}:6380 ${IP}:6381 ${IP}:6382 ${IP}:6383 ${IP}:6384

    for port in 6379 6380 6381; do
      redis-sentinel /redis-conf/sentinel-6379.conf &
    done

    tail -f /var/log/supervisor/redis*.log
else
  exec "$@"
fi
