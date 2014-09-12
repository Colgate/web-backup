#! /bin/bash

#############################################################
# name:        Web-Backup                                   # 
# author:      Colgate                                      #
# description: Full backup script for web content,          #
#              configurations, and databases.               #
#############################################################  

######## Configuration variables go here ########

# Location of your nginx config files. [Default = /etc/nginx/conf.d]
serverdir=/etc/nginx/conf.d

# Directory you will keep your backup files [Default = /backups/web]
backupdir=/backups/web

# Number of days to keep backups for. [Default = 30]
retain=30


######## Don't modify below this line unless you really know what you're doing. Or if you like breaking things. ########

today=$(date +"%m-%d-%Y")

echo -e "\nBackup run started for $today\n\n\tRemoving backups older than $retain days";
find $backupdir -type f -name "*.tar.gz" -mtime $((retain - 1)) -exec echo -e "\tRemoving {}" \; -delete;

for i in $(/bin/ls $serverdir | egrep -v "default|example"); 
do
    # Grab some variables from the server block.
    domain=$(awk '/server_name/ {print $2}' $serverdir/$i | head -n 1)
    docroot=$(dirname $(awk '/root/ {print $2}' $serverdir/$i))
    logpath=$([ ! -z $(awk '/error_log/ {print $2}' $serverdir/$i) ] && dirname $(awk '/error_log/ {print $2}' $serverdir/$i))
    # Verify everything looks proper before beginning.
    [[ ! -d $backupdir ]] && { echo -e "\tBackup directory does not exist. Creating."; mkdir -p $backupdir; }
    [[ ! -d $backupdir/$domain ]] && { echo -e "\tBackup location for this account does not exist. Creating."; mkdir -p $backupdir/$domain; }
    [[ -e $backupdir/$domain/backup_$domain-$today.tar.gz ]] && echo -e "\n\tIt looks like a backup matching today's date was already created for $domain. Cannot proceed." || {
        echo -e "\n\tBeginning backup process for $domain.\n\tCreating temporary directory structure.";
        mkdir -p $backupdir/backup-$domain/{logs,mysql,configs,homedir};
        echo -e "\tLocating and dumping any relevant databases."
        mysql -sse "show databases like \"$(cut -d/ -f3 <<< $docroot)\_%\"" | while read db; do echo -e "\t\tDumping $db"; mysqldump $db > $backupdir/backup-$domain/mysql/$db.sql; done
        echo -e "\tCopying over the files.";
        rsync -avP $docroot/ $backupdir/backup-$domain/homedir/ &>/dev/null;
        echo -e "\tCopying the configuration files.";
        rsync -avP $serverdir/$i /etc/named/$domain.zone /var/named/$domain.db $backupdir/backup-$domain/configs/ &>/dev/null;
        [[ -d /home/vmail/mail/$domain ]] && {
           echo -e "\tGetting mail.";
           mkdir $backupdir/backup-$domain/mail;
           rsync -avP /home/vmail/mail/$domain $backupdir/backup-$domain/mail &>/dev/null;
           grep $domain /etc/vmail/mailusers > $backupdir/backup-$domain/configs/mailusers
        }
        [[ -n $logpath ]] && {
            echo -e "\tCopying the log files.";
            rsync -avP $logpath/ $backupdir/backup-$domain/logs/ &>/dev/null;
        }
        echo -e "\tCopying the log files.";
        rsync -avP $logpath 
        echo -e "\tCreating archive.";
        tar -zcf $backupdir/$domain/backup_$domain-$today.tar.gz -C $backupdir backup-$domain
        echo -e "\tCleaning up temporary directory.";
        rm -rf $backupdir/backup-$domain/
        echo -e "\n\tDone backing up $domain. File was created at $backupdir/$domain/backup_$domain-$today.tar.gz."
    }
done

echo -e "\nBackup run completed for $today."
