#!/bin/bash
# Following a tutorial on https://www.digitalocean.com/community/tutorials/how-to-configure-a-galera-cluster-with-mariadb-on-ubuntu-12-04-servers

ip=`ifconfig eth0 | grep "inet addr"| cut -d ":" -f2 | cut -d " " -f1`
nodeName=`hostname`
nodePrefix="$5"
masterName="${nodePrefix}1"

clusterName="$6"
dbName="$1"
dbUser="$2"
dbPassword="$3"
maintPassword="$4"

nodeCount=$7

ips="${nodePrefix}1"
for (( i=2 ; i<=nodeCount ; i++ ))
do
    ips="${ips},${nodePrefix}${i}"
done

echo "*** Executing script on $nodeName ($ip)"
echo "**"
echo "** Whoami: `whoami`"
echo "** Whoami (sudo): `sudo whoami`"
echo "** home: `$HOME`"
echo "** pwd: `pwd`"
echo "**"
echo "** Installing MariaDB Galera"
echo "**"
sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db
sudo add-apt-repository 'deb http://mirror.jmu.edu/pub/mariadb/repo/5.5/ubuntu trusty main'
sudo apt-get update

export DEBIAN_FRONTEND=noninteractive
echo "mariadb-galera-server-5.5 mysql-server/root_password password $dbPassword" | sudo debconf-set-selections
echo "mariadb-galera-server-5.5 mysql-server/root_password_again password $dbPassword" | sudo debconf-set-selections

sudo apt-get install mariadb-galera-server galera -qq -y

if [ "$nodeName" == "$masterName" ]
then
    echo "** Setting password for debian-sys-maint user in MySQL DB (first node)"
    sudo service mysql start
    mysql -uroot -p$dbPassword -e "SET PASSWORD FOR 'debian-sys-maint'@'localhost' = PASSWORD('$maintPassword')"
fi
echo "**"
echo "** Setting password for debian-sys-maint user in debian.cnf (all nodes)"
echo "**"
sudo service mysql stop
sudo sed -i "s/\password =.*/password = $maintPassword/" /etc/mysql/debian.cnf

echo "**"
echo "** Writing cluster.cnf"
echo "**"
cat > /tmp/cluster.cnf << eof
    [mysqld]
    query_cache_size=0
    binlog_format=ROW
    default-storage-engine=innodb
    innodb_autoinc_lock_mode=2
    query_cache_type=0
    bind-address=0.0.0.0

    # Galera Provider Configuration
    wsrep_provider=/usr/lib/galera/libgalera_smm.so
    #wsrep_provider_options="gcache.size=32G"

    # Galera Cluster Configuration
    wsrep_cluster_name="$clusterName"
    wsrep_cluster_address="gcomm://$ips"

    # Galera Synchronization Congifuration
    wsrep_sst_method=rsync
    #wsrep_sst_auth=user:pass

    # Galera Node Configuration
    wsrep_node_address="$ip"
    wsrep_node_name="$nodeName"
eof

sudo mv /tmp/cluster.cnf /etc/mysql/conf.d/

if [ "$nodeName" == "$masterName" ]
then
    echo "**"
    echo "** Starting mysqld on $nodeName with NEW-CLUSTER"
    echo "**"
    # init cluster
    sudo service mysql start --wsrep-new-cluster

    # Create new global user
    mysql -uroot -p$dbPassword -e"CREATE DATABASE $dbName"
    mysql -uroot -p$dbPassword -e"CREATE USER '$dbUser'@'%' IDENTIFIED BY '$dbPassword';"
    mysql -uroot -p$dbPassword -e"GRANT ALL PRIVILEGES ON *.* TO '$dbUser'@'%' WITH GRANT OPTION;"
    mysql -uroot -p$dbPassword -e"FLUSH PRIVILEGES;"

    # workaround because of an issue with socket on mysql1
    sudo service mysql stop
    echo "sudo service mysql start --wsrep-new-cluster" | at now + 1 minutes

else
    running="`sudo service mysql status | grep Uptime`"
    while [[ $running == "" ]]; do
            echo "**"
            echo "** Starting mysqld on $nodeName (other)"
            echo "**"
            sudo service mysql start

            running="`sudo service mysql status | grep Uptime`"
            sleep 5
    done
fi
echo "***"
echo "*** Finished execution of script on $nodeName ($ip)"