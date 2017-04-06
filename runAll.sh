#!/usr/bin/env bash

hadoop fs -mkdir -p /apps/spark

cp /home/mapr/maprts-docker-jars/spark-streaming-kafka-0-9_2.11-2.0.1-mapr-1611.jar /opt/mapr/spark/spark-2.0.1/jars/.
sh /opt/mapr/spark/spark-2.0.1/sbin/stop-master.sh
sh /opt/mapr/spark/spark-2.0.1/sbin/start-master.sh
sh /opt/mapr/spark/spark-2.0.1/sbin/start-slaves.sh

cd /home/mapr/maprts-docker-jars && su mapr -c "hadoop fs -put lr.model /user/mapr/."
su mapr -c "maprcli stream create -path /sample-stream"
su mapr -c "maprcli stream edit -path /sample-stream -produceperm p -consumeperm p -topicperm p"
su mapr -c "maprcli stream topic create -path /sample-stream  -topic sensor1-region1"
su mapr -c "nohup sh runStream.sh > stream.log &"
su mapr -c "nohup sh runTs.sh > ts.log &"
