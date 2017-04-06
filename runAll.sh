#!/usr/bin/env bash

service sshd start

IP=$(ip addr show eth0 | grep -w inet | awk '{ print $2}' | cut -d "/" -f1)

#echo -e "${IP}\t$(hostname -f).mapr.io\t$(hostname) " >> /etc/hosts
echo -e "${IP}\tdemo.mapr.io\tdemo " >> /etc/hosts

mkdir -p /opt/mapr/disks
if [[ ! -f /opt/mapr/disks/docker.disk ]]
then
        fallocate -l 20G /opt/mapr/disks/docker.disk
fi
DISKLIST=/opt/mapr/disks/docker.disk

/opt/mapr/server/mruuidgen > /opt/mapr/hostid
cat /opt/mapr/hostid > /opt/mapr/conf/hostid.$$

hostname demo.mapr.io
echo demo.mapr.io > /etc/hostnmae
echo demo.mapr.io > /opt/mapr/hostnmae

cp /proc/meminfo /opt/mapr/conf/meminfofake

MEMTOTAL=6291456
sed -i "/^MemTotal/ s/^.*$/MemTotal:     ${MEMTOTAL} kB/" /opt/mapr/conf/meminfofake
sed -i "/^MemFree/ s/^.*$/MemFree:     ${MEMTOTAL-10} kB/" /opt/mapr/conf/meminfofake
sed -i "/^MemAvailable/ s/^.*$/MemAvailable:     ${MEMTOTAL-10} kB/" /opt/mapr/conf/meminfofake

sed -i 's/AddUdevRules(list/#AddUdevRules(list/' /opt/mapr/server/disksetup

#/opt/mapr/server/configure.sh -C ${IP} -Z ${IP} -N dockerdemo.mapr.com -RM ${IP} -u mapr -D ${DISKLIST} -noDB
#/opt/mapr/server/configure.sh -C ${IP} -Z ${IP} -D ${DISKLIST} -N ${CLUSTERNAME}.mapr.io -u mapr -g mapr -noDB -RM ${IP}
memNeeded=512 /opt/mapr/server/configure.sh -C ${IP} -Z ${IP} -D ${DISKLIST} -N demo.mapr.io -u mapr -g mapr -no-autostart


change_warden_conf ()
{
  echo "Changing /opt/mapr/warden.conf"
  Conf[0]="service.command.nfs.heapsize.min"
  Conf[1]="service.command.nfs.heapsize.max"
  Conf[2]="service.command.hbmaster.heapsize.min"
  Conf[3]="service.command.hbmaster.heapsize.max"
  Conf[4]="service.command.hbregion.heapsize.min"
  Conf[5]="service.command.hbregion.heapsize.max"
  Conf[6]="service.command.cldb.heapsize.min"
  Conf[7]="service.command.cldb.heapsize.max"
  Conf[8]="service.command.webserver.heapsize.min"
  Conf[9]="service.command.webserver.heapsize.max"
  Conf[10]="service.command.mfs.heapsize.percent"
  Conf[11]="service.command.mfs.heapsize.min"
  Conf[12]="service.command.mfs.heapsize.max"
  Conf[13]="isDB"

  Val[0]="64"
  Val[1]="64"
  Val[2]="128"
  Val[3]="128"
  Val[4]="256"
  Val[5]="256"
  Val[6]="256"
  Val[7]="256"
  Val[8]="128"
  Val[9]="128"
  Val[10]="15"
  Val[11]="512"
  Val[12]="512"
  Val[13]="false"

  for i in "${!Conf[@]}"; do
    sed -i s/${Conf[$i]}=.*/${Conf[$i]}=${Val[$i]}/ /opt/mapr/conf/warden.conf
  done
}


sleep 30

### For Spark

sed -i "/^export SPARK_MASTER_HOST/ s/^.*$/export SPARK_MASTER_HOST=demo.mapr.io/" /opt/mapr/spark/spark-2.0.1/conf/spark-env.sh
sed -i "/^export SPARK_MASTER_IP/ s/^.*$/export SPARK_MASTER_IP=${IP}/" /opt/mapr/spark/spark-2.0.1/conf/spark-env.sh


# Change the warden.conf file with new params.
change_warden_conf

# Start mapr-zookeeper and mapr-warden with new values
service mapr-zookeeper start
service mapr-warden start

#sleep 60
i=0
while [ "$i" -le "180" ]
do
  maprcli node cldbmaster 2> /dev/null
  if [ $? -eq 0 ]; then
    break
  fi

  sleep 5
  i=$[i+5]
done


## For Spark
hadoop fs -mkdir -p /apps/spark && hadoop fs -chmod 777 /apps/spark

echo "This container IP : ${IP}"

sleep 60

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
