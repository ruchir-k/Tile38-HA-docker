## Introduction

- A three Tile38 db and three Redis Sentinel, master/slave architecture is implemented to ensure High Availability
- A docker compose for the same is made for straight forward setup

## Tile38-Redis Sentinel Connection

- A redis client can be used to connect to a Tile38 db docker container or a Redis Sentinel at an exposed endpoint
The following client was successfully used to test the R/W to the db
    - Lettuce (Java & Kotlin)
- The exposed ports of Tile38 are as follows:

```
tile38-1: 9851
tile38-2: 9852
tile38-3: 9853
```

> tile38-1 exposed at 9851 is configured to be the master on starting up, if it goes down another tile38 instance becomes the master
> 
- The exposed ports of Sentinel are as follows:

```
redis-sentinel1: 5000
redis-sentinel2: 5001
redis-sentinel3: 5002
```

## Tile38 Config

https://tile38.com/topics/configuration

- The config file is to be mounted to the data/ directory of the tile38 container, specifying the relevant fields for the master and slaves respectively.

## Redis Sentinel Config

[High availability with Redis Sentinel](https://redis.io/docs/management/sentinel/)

- The sentinel.conf file is to be mounted to the data/ directory of the tile38 container, specifying the relevant fields for the QUORUM, DOWN AFTER MILLISECONDS, PARALLEL SYNC and FAILOVER TIMEOUT respectively.
    - port is the portnumber at which the sentinel can be accessed.
    - The *quorum* is the number of Sentinels that need to agree about the fact the master is not reachable, in order to really mark the master as failing, and eventually start a failover procedure if possible.
    - *down-after-milliseconds* is the time in milliseconds an instance should not be reachable (either does not reply to our PINGs or it is replying with an error) for a Sentinel starting to think it is down.
    - *parallel-syncs* sets the number of replicas that can be reconfigured to use the new master after a failover at the same time. The lower the number, the more time it will take for the failover process to complete, however if the replicas are configured to serve old data, you may not want all the replicas to re-synchronize with the master at the same time. While the replication process is mostly non blocking for a replica, there is a moment when it stops to load the bulk data from the master. You may want to make sure only one replica at a time is not reachable by setting this option to the value of 1.

- The following is the sentinel.conf file used in this repo

```
Example sentinel.conf can be downloaded from http://download.redis.io/redis-stable/sentinel.conf

port $SENTINEL_PORT

sentinel monitor mymaster 127.0.0.1 9851 2

sentinel down-after-milliseconds mymaster 3000

sentinel parallel-syncs mymaster 1

sentinel failover-timeout mymaster 18000
```


## Data Backup with AOF

> Append-only file (AOF) is a logging mechanism that writes to a log file on disk every write operation performed on a Redis database. The log file is used to reconstruct the database in the event of a crash or failure.
> 

- When a tile38 docker container (or compose) is stopped, it persists the AOF. Hence on bringing the docker container (or compose) up the AOF which has the data stored from the previous writes has this stored data available again on the access endpoints.
- For the case of complete failover of the three tile38 db’s the AOF file from another location (ideally from the S3 bucket where the AOF file is to be written every 30 minutes/1 hour) can be copied to the new master container before it is started.

The following is the Dockerfile for the master:

```
FROM tile38/tile38:latest

WORKDIR /data
COPY ./config /data/
# COPY ./appendonly.aof(set this copy from location appropriately) /data/   
EXPOSE 9851
CMD [ "tile38-server", "-d", "/data", "--appendonly", "yes","-vv", "-p", "9851" ]
RUN echo "Running master......"
```


## Local Testing

- The mapping of ports by docker daemon in MacOS prevents this setup to work correctly. Hence, this has to be tested in a linux system. 
The testing done here was on a *VM running linux* on Mac
- To check the details of a tile38 db, use the following curl command where portnumber is one of 9851, 9852 or 9853.

```
curl [http://127.0.0.1:<*portnumber*>/info](http://127.0.0.1:5000/info)
```

## Lettuce client connection to Redis Sentinel

- Two possible ways to connect to sentinels:

```
val redisURI = RedisURI.Builder.sentinel("localhost", 5000, "mymaster")
        .withSentinel("localhost", 5001).withSentinel("localhost",5002).build()
val client = RedisClient.create(redisURI)
```

```
val client = RedisClient.create("redis-sentinel://localhost:5000,localhost:5001,localhost:5002#mymaster")
```


## Client Logs(Redis Sentinel) for Master failover

```
redis-sentinel1  | 1:X 01 Apr 2024 06:13:24.491 * +slave-reconf-inprog slave 127.0.0.1:9853 127.0.0.1 9853 @ mymaster 127.0.0.1 9851
redis-sentinel1  | 1:X 01 Apr 2024 06:13:24.552 # -odown master mymaster 127.0.0.1 9851
redis-sentinel2  | 1:X 01 Apr 2024 06:13:26.518 # +sdown slave 127.0.0.1:9851 127.0.0.1 9851 @ mymaster 127.0.0.1 9852
redis-sentinel3  | 1:X 01 Apr 2024 06:13:26.576 # +sdown slave 127.0.0.1:9851 127.0.0.1 9851 @ mymaster 127.0.0.1 9852
tile38-1 exited with code 0
tile38-1 exited with code 137
redis-sentinel1  | 1:X 01 Apr 2024 06:13:41.455 # +failover-end-for-timeout master mymaster 127.0.0.1 9851
redis-sentinel1  | 1:X 01 Apr 2024 06:13:41.456 # +failover-end master mymaster 127.0.0.1 9851
redis-sentinel1  | 1:X 01 Apr 2024 06:13:41.458 * +slave-reconf-sent-be slave 127.0.0.1:9853 127.0.0.1 9853 @ mymaster 127.0.0.1 9851
redis-sentinel1  | 1:X 01 Apr 2024 06:13:41.459 # +switch-master mymaster 127.0.0.1 9851 127.0.0.1 9852
redis-sentinel1  | 1:X 01 Apr 2024 06:13:41.459 * +slave slave 127.0.0.1:9853 127.0.0.1 9853 @ mymaster 127.0.0.1 9852
redis-sentinel1  | 1:X 01 Apr 2024 06:13:41.460 * +slave slave 127.0.0.1:9851 127.0.0.1 9851 @ mymaster 127.0.0.1 9852
```

> Redis Sentinel has two different concepts of being down, one is called a Subjectively Down condition (SDOWN) and is a down condition that is local to a given Sentinel instance. Another is called Objectively Down condition (ODOWN) and is reached when enough Sentinels (at least the number configured as the *quorum* parameter of the monitored master) have an SDOWN condition, and get feedback from other Sentinels using the *SENTINEL is-master-down-by-addr* command.
> 
- In the above failover logs for clients, i.e. redis-sentinel2 and redis-sentinel3 both give sdown state for following the original master, since it has gone down.
- Post sufficient number of sdown votes are achieved for quorum, the switch-master mymaster 127.0.0.1 9851 127.0.0.1 9852 statement is executed.
This statement indicates the *switchover* of the master for **tile38-1 exposed at port 9851* to *tile38-2 exposed at port 9852**

## (Observation: )

- In the case of failure(stopping) of the original tile38 master, a tile38 slave instance is elected as master. On restoring the original tile38 master, the tile38 slave instance which was made the master, remains the master.

## (Note: ) Host Networking Mode

- If you use the host network mode for a container, that container's network stack isn't isolated from the Docker host (the container shares the host's networking namespace), and the container doesn't get its own IP-address allocated. For instance, if you run a container which binds to port 80 and you use host networking, the container's application is available on port 80 on the host's IP address.
- The host networking driver only works on Linux hosts, and is not supported on Docker Desktop for Mac, Docker Desktop for Windows, or Docker EE for Windows Server.

## (Note: ) Port Mapping in Docker

- The [*expose*](https://docs.docker.com/engine/reference/builder/#expose) keyword in a Dockerfile tells Docker that a container listens for traffic on the specified port.
Exposing a port doesn't make it available when you run a container.  To do that, you need to *publish* your ports. Depending on how you want to use the port, you need to map it, too.
- You publish ports when you run a container with the *-p* or *-P* command-line arguments.

## (Note:) Port Mapping issues in ECS (Why this wasn’t implemented)

- Redis Sentinels interact with each other and Tile38 instances through IP Addresses.
- In the case of ECS controlled EC2 instances hosting these Redis Sentinel and Tile38 instances, the particular EC2 instance which hosts these Redis Sentinel and Tile38 instances is not fixed but dynamically handled by ECS.
- The dynamic nature of exposed IP Addresses and Ports is the primary reason to not go ahead with Redis Sentinel.
- Using Kubernetes to mitigate the issue of dynamic IP’s can be considered in the future if deemed necessary.
