#!/usr/bin/env bash

hadoop fs -mkdir -p /apps/spark
chown mapr:mapr /var/log/opentsdb
cp /etc/opentsdb/opentsdb.conf /etc/opentsdb/opentsdb.conf.orig

cat <<EOF > /etc/opentsdb/opentsdb.conf
tsd.network.port = 4242
tsd.http.staticroot = /usr/share/opentsdb/static/
tsd.http.cachedir = /tmp/opentsdb
tsd.core.plugin_path = /usr/share/opentsdb/plugins
tsd.storage.enable_compaction = true

# MapR-DB does not utilize this value, but it must be set to something
tsd.storage.hbase.zk_quorum = localhost:5181

tsd.storage.hbase.data_table = $TBL_PATH/tsdb
tsd.storage.hbase.uid_table = $TBL_PATH/tsdb-uid
tsd.storage.hbase.meta_table = $TBL_PATH/tsdb-meta
tsd.storage.hbase.tree_table = $TBL_PATH/tsdb-tree

tsd.storage.fix_duplicates = true

tsd.core.auto_create_metrics = true
tsd.http.request.enable_chunked = true
EOF

mkdir /root/opentsdb && cd /root/opentsdb/ &&  git clone https://github.com/mengdong/opentsdb-mapr.git
/root/opentsdb/opentsdb-mapr/install.sh
sed -i -e "s/^TABLES_PATH=.*$/TABLES_PATH=\"$TBL_PATH_E\"/" /root/opentsdb/opentsdb-mapr/create_table.sh
cp /root/opentsdb/opentsdb-mapr/create_table.sh /tmp/.
su mapr -c /tmp/create_table.sh
sleep 5

chkconfig opentsdb on
service opentsdb start

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
