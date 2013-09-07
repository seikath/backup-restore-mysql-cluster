# This is my README

This epg-mysql-cluster backup restore script:
install : 

git clone https://github.com/seikath/backup-restore-mysql-cluster

usage: 
cd epg-mysq-cluster/bin
chmod +x epg.mysql.cluster.restore.sh

edit epg.mysql.cluster.restore.conf and put the proper IP values
put the proper relative BACKUP directory path - its in the NDBD data node direcotry/

the ssh communication at the moment is disabled in a view to avoid installing ssh keys etc.

execute as :

./epg.mysql.cluster.restore.sh 

during the restore in case of failure some hints will be proposed.
you may find then later in the separated log file that will be created.

Cheers

Slackware4Life!


