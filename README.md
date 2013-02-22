# This is my README

This epg-mysql-cluster restore script:
install : 

git clone git@bitbucket.org:seikath/epg-mysql-cluster.git

usage: 
cd epg-mysq-cluster/bin
chmod +x epg.mysql.cluster.restore.sh

edit epg.mysql.cluster.restore.conf and put the proper IP values
put the proper relatime BACKUP directory path /its in the NDBD data node direcotry/

the ssh communication at the moment is disabled in a view to avoid installing ssh keys etc.

execute as :

./epg.mysql.cluster.restore.sh 

during the restore in case of failure some hints will be proposed.
you may find then later in the separated log file that will be created.

Cheers

Slackware4Life!


