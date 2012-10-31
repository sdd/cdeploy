#!/bin/bash
#############################################
# Gitolite CakePHP auto-deploy setup script #
#############################################

#======================================================
# Load dependencies
#======================================================
# Creds: https://github.com/rudimeier/bash_ini_parser
. read_ini.sh
. bashfuncs.sh

#======================================================
# Default Settings
#======================================================
DEFAULT_BRANCH=live
DEFAULT_GITOLITESERVER=localhost
DEFAULT_CAKELOCATION=/usr/local/cakephp/cakephp-2.2/lib/Cake
DEFAULT_VHOSTS=/var/www/vhosts

#======================================================
# Show Help
#======================================================
usage(){
        echo "Usage: auto-deploy-setup.sh -d/--domain domain [-r/--repo repo] [-u/--user username] [-b/--branch branch] [-c/--cake cakelocation] [-v/--vhosts vhosts_location]"
	echo ""
	echo "domain: The domain name that the site will be serving. This affects the directory name within vhosts, and the apache config."
	echo ""
	echo "repo: This is the name of the repo within gitolite that is to be checked out into the webroot for the domain. If this is not specified, the script will use the lst fragment of the domain prior to the TLD. e.g. www.testsite.co.uk as the domain will guess testsite as the repo name."
	echo ""
	echo "gitolite: The host name of the gitolite server, accessed via SSH. Default localhost."
	echo ""
	echo "branch: The branch of the git repository to check out. Defaults to 'live'."
	echo ""
	echo "user: The name of the user to be created on the server that will have the site's webroot folder as their home. This user will be created if it does not already exist. Defaults to the repo name concatenated with the branch name."
	echo ""
	echo "cake: the location of CakePHP's Cake folder, the one that contains all the core CakePHP code. this is lib/Cake within a freshly checked out CakePHP repo. The site will symlink to this, allowing multiple sites to share the same CakePHP core code. This simplifies security upgrades and uses less space on the server and the source repo. Defaults to /usr/local/cakephp/cakephp-2.2/lib/Cake (admittedly this is somewhat arbitrary, but it is what I use. I have multiple versions of cakephp within /usr/local/cakephp for sites that use older versions of CakePHP that have yet to be ported to newer CakePHP versions."
	echo ""
	echo "vhosts: the location in the filesystem where all of apache's sites are hosted. defaults to /var/www/vhosts"
}

#======================================================
# Parse INI file
#======================================================
function parse_ini() {
	if [ -e "$1" ]; then
		read_ini "$1"
	fi
}

#======================================================
# Parse command line options
#======================================================
function parse_opts() {
 	OPTS=`getopt -o hd:r:u:b:c:v:fg: -l domain:,repo:,gitolite:,user:,branch:,cake:,vhosts:,config:,help -n auto-deploy-setup -- "$@"`
	if [ $? != 0 ]; then exit 1; fi

	eval set -- "$OPTS"

	while true ; do
		case "$1" in
			-d) DOMAINNAME=$2; shift 2;;
			-r) PROJECTNAME=$2; shift 2;;
			-g) GITOLITESERVER=$2; shift 2;;
			-u) WEBUSERNAME=$2; shift 2;;
			-b) BRANCH=$2; shift 2;;
			-c) CAKELOCATION=$2; shift 2;;
			-v) VHOSTS=$2; shift 2;;
			# -f) parse_ini $2; shift 2;;
			-h) usage; exit 0;;
			--domain) DOMAINNAME=$2; shift 2;;
			--repo) PROJECTNAME=$2; shift 2;;
			--gitolite) GITOLITESERVER=$2; shift 2;;
			--user) WEBUSERNAME=$2; shift 2;;
			--branch) BRANCH=$2; shift 2;;
			--cake) CAKELOCATION=$2; shift 2;;
			--vhosts) VHOSTS=$2; shift 2;;
			# --config) parse_ini $2; shift 2;;
			--help) usage; exit 0;;
			--) shift; break;;
		esac
	done

	# populate missing arguments from defaults
	if [ -z "$BRANCH" ]; then BRANCH=$DEFAULT_BRANCH; fi
	if [ -z "$VHOSTS" ]; then VHOSTS=$DEFAULT_VHOSTS; fi
	if [ -z "$CAKELOCATION" ]; then CAKELOCATION=$DEFAULT_CAKELOCATION; fi 
	if [ -z "$GITOLITESERVER" ]; then GITOLITESERVER=$DEFAULT_GITOLITESERVER; fi 

	# populate missing implied arguments from sensible guesses
	if [ -z "$PROJECTNAME" ]; then
		if [ -n "$DOMAINNAME" ]; then
			# set project name as domain name without tld or subdomain
			domainparts=$(echo $DOMAINNAME | tr "." "\n")

			declare -a tld=(com org net co uk)

			for x in $domainparts; do
				if [ $(contains "${tld[@]}" "$x") == "y" ]; then break; fi;
				DOMAIN_GUESS=$x
			done

			if [ -n "DOMAIN_GUESS" ]; then
				PROJECTNAME=$DOMAIN_GUESS
			fi
		fi
	fi

	if [ -z "$WEBUSERNAME" ]; then
		if [ -n "$PROJECTNAME" ]; then
			WEBUSERNAME="$PROJECTNAME$BRANCH"
		fi
	fi
}

function show_opts() {
	echo "Domain Name:		$DOMAINNAME"
	echo "Repo/Project Name:	$PROJECTNAME"
	echo "Gitolite Server:	$GITOLITESERVER"
	echo "User Name: 		$WEBUSERNAME"
	echo "Branch:			$BRANCH"
	echo "Cake Location:		$CAKELOCATION"
	echo "Vhosts:			$VHOSTS"
}

parse_ini auto-deploy-setup.ini
parse_opts $@
show_opts

if [ -z "$DOMAINNAME" ] || [ -z "$PROJECTNAME" ] || [ -s "$GITOLITESERVER" ] || [ -z "$WEBUSERNAME" ] || [ -z "$BRANCH" ] || [ -z "$CAKELOCATION" ] || [ -z "$VHOSTS" ]; then
	echo ""
	echo "*** Not all of the required arguments are present."
	echo ""
	usage
	exit 1
fi

read -p "Proceed? (y/n)"
if [ "$REPLY" != "y" ]; then
	echo "Exiting."
	exit 0
fi

#======================================================
#Create live folder, eg /var/www/vhosts/newsite.co.uk
#======================================================
if [ ! -d  "$VHOSTS/$DOMAINNAME" ]; then
	read  -p "Create subfolder for site in $VHOSTS ? (y/n)"
	if [ "$REPLY" == "y" ]; then
		mkdir -p "$VHOSTS/$DOMAINNAME" "$VHOSTS/$DOMAINNAME/logs"
		touch "$VHOSTS/$DOMAINNAME/logs/access.log"
		touch "$VHOSTS/$DOMAINNAME/logs/error.log"
	fi
	if [ ! -d  "$VHOSTS/$DOMAINNAME" ]; then
		echo "Failed to create the folder $VHOSTS/$DOMAINNAME. Cannot continue."
		if [ "`id -un`" != "root" ]; then
			echo "Rerun this script using sudo or as root."
		fi
		exit 1
	fi 
else
	echo "$VHOSTS/$DOMAINNAME already exists."
fi

#======================================================
#Create user, set user's home as webroot
#======================================================
if [ -z "`id -u $WEBUSERNAME 2>/dev/null`" ]; then
	read  -p "Create user for webroot (y/n)?"
	if [ "`id -un`" == "root" ]; then
		if [ "$REPLY" == "y" ]; then
			adduser \
				--disabled-password \
				--home $VHOSTS/$DOMAINNAME \
				--no-create-home \
				--gecos "user for $DOMAIN webroot" \
				--quiet \
				$WEBUSERNAME
		fi
		if [ -z "`id -u $WEBUSERNAME 2>/dev/null`" ]; then
			echo "Failed to create the user $WEBUSERNAME."
			exit 1
		fi
	else
		echo "Rerun this script using sudo or as root."
		exit 1
	fi
else
	echo "user $WEBUSERNAME already created."
fi

chown -R $WEBUSERNAME:$WEBUSERNAME $VHOSTS/$DOMAINNAME
RETVAL=$?
if [ "$RETVAL" -ne 0 ]; then
	echo "Failed to change the ownership of $VHOSTS/$DOMAINNAME to $WEBUSERNAME."
	if [ "`id -un`" != "root" ]; then
		echo "Rerun this script using sudo or as root."
	fi
	echo "Exiting."
	exit 1
fi

#======================================================
#Create user's SSH key and add to gitolite
#======================================================
read  -p "Create SSH key and add to gitolite (y/n)?"
if [ "$REPLY" == "y" ]; then
	if [ ! -e $VHOSTS/$DOMAINNAME/.ssh/id_rsa ]; then
		sudo -u $WEBUSERNAME ssh-keygen -C $WEBUSERNAME -f $VHOSTS/$DOMAINNAME/.ssh/id_rsa -N ""
	fi
	sudo -u $WEBUSERNAME cp $VHOSTS/$DOMAINNAME/.ssh/id_rsa.pub /tmp/$WEBUSERNAME.pub
	echo "New SSH key copied to /tmp/$WEBUSERNAME_rsa.pub."
	echo "make the following changes to the gitolite-admin repo:"
	echo "1) use SCP to copy the SSH key to the admin repo"
	echo "    e.g. scp ubuntu@cogentec.co.uk:/tmp/$WEBUSERNAME.pub keydir/"
	echo ""
	echo "2) add the user as a read only user into the config for the repo"
	echo "    e.g. R 		=	$WEBUSERNAME"
	echo ""
	echo "3) Add, Commit and push the changes"
	echo "    e.g. git add conf; git add keydir; git commit -m \"Added $WEBUSERNAME\"; git push"
	echo ""
	read -p "Hit enter when complete" -n1 -s
	rm /tmp/$WEBUSERNAME.pub
fi

#======================================================
# Allow git user to ssh to new user.
#======================================================
if [ "$GITOLITESERVER" == "localhost" ]; then
	if [ ! -e /home/git/.ssh/id_rsa ]; then
		echo "Git user has no SSH key - creating one"
		sudo -u git ssh-keygen -f /home/git/.ssh/id_rsa -N ""
	fi
	cat /home/git/.ssh/id_rsa.pub >> $VHOSTS/$DOMAINNAME/.ssh/authorized_keys
else
	echo "Your gitolite server is not on this machine."
	echo ""
	echo "The id_rsa.pub of the gitolite server's git user is still required."
	echo "This should be present as /home/git/.ssh/id_rsa.pub on the gitolite server."
	echo "if this file is not present, SSH to the gitolite server as root or a user with"
	echo "sudo permission, and execute the following:"
	echo ""
	echo "    sudo -u git ssh-keygen -f /home/git/.ssh/id_rsa -N \"\""
	echo ""
	echo "once this is done, or if it is already present, scp it to this server"
	echo " in the location /tmp/git.pub. This can be done by executing"
	echo "the following command whilst logged in to the gitolite server as root or a sudo user:"
	echo ""
	echo "    sudo scp /home/git/.ssh/id_rsa.pub ubuntu@$DOMAINNAME:/tmp/git.pub"
	echo ""
	echo "(Assuming that $DOMAINNAME points to this server)."
	read -p "Hit enter to continue once this has been done" -n1 -s
	cat /tmp/git.pub >> $VHOSTS/$DOMAINNAME/.ssh/authorized_keys
	rm /tmp/git.pub
fi

#======================================================
# clone the repo into httpdocs and checkout the branch
#======================================================
read  -p "checkout $BRANCH as user $WEBUSERNAME (y/n)?"
if [ "$REPLY" == "y" ]; then
	sudo -u $WEBUSERNAME bash -c "cd $VHOSTS/$DOMAINNAME;\
mkdir -p httpdocs;\
cd httpdocs;\
git clone git@$GITOLITESERVER:$PROJECTNAME app; \
cd app;\
git fetch;\
git pull origin live;\
git checkout $BRANCH;\
git submodule update -i -r;\
tar -xzvf deployment/httpdocs_content.tar.gz -C ..; \
ln -s $CAKELOCATION ../lib/Cake; \
chmod -R 777 tmp\
"
fi

#======================================================
# install the post-receive hook
#======================================================
read  -p "Install git post-receive hook? y/n"
if [ "$REPLY" == "y" ]; then
	if [ "$GITOLITESERVER" == "localhost" ]; then
		if [ -e "$VHOSTS/$DOMAINNAME/httpdocs/app/deployment/post-receive" ]; then
		        echo "Installing post-receive hook"
			cp -a $VHOSTS/$DOMAINNAME/httpdocs/app/deployment/post-receive /home/git/repositories/$PROJECTNAME.git/hooks/
			chown git:git /home/git/repositories/$PROJECTNAME.git/hooks/post-receive
			chmod u+x /home/git/repositories/$PROJECTNAME.git/hooks/post-receive 
		else
			echo "post-receive hook not found ($VHOSTS/$DOMAINNAME/httpdocs/app/deployment/post-receive)"
		fi
	else
		echo "2"
	fi
fi

#======================================================
# configure apache to serve on this domain
#======================================================
if [ ! -e /etc/apache2/sites-available/$DOMAINNAME ] || [ ! -L /etc/apache2/sites-enabled/$DOMAINNAME ]; then
	read  -p "Configure Apache? y/n"
	if [ "$REPLY" == "y" ]; then
		cd /etc/apache2/sites-available
		if [ ! -e /etc/apache2/sites-available/$DOMAINNAME ]; then
			cp -a template.conf $DOMAINNAME
			sed -i "s/DOMAINNAME/$DOMAINNAME/g"  $DOMAINNAME
			RESTART_APACHE=yes
		else
			echo "Apache config file /etc/apache2/sites-available/$DOMAINNAME already exists."
		fi

		if [ ! -L /etc/apache2/sites-enabled/$DOMAINNAME ]; then
			a2ensite $DOMAINNAME
			RESTART_APACHE=yes
		else
			echo "The apache site is already enabled."
		fi

		if [ -n "$RESTART_APACHE" ]; then
			apache2ctl restart
		fi
	fi
else
	echo "Apache already configured."
fi

#======================================================
# Copy over a valid database.php file
#======================================================
read  -p "Install Database Config? y/n"
if [ "$REPLY" == "y" ]; then
	echo "Using SCP, copy a valid database.php file to /tmp/database-$PROJECTNAME.php"
	echo "This file will be moved to the checked out repo to use as the"
	echo "Config/database.php file. e.g:"
	echo ""
	echo "    scp Config/database.php ubuntu@cogentec.co.uk:/tmp/database-$PROJECTNAME.php"
	echo ""
	read -p "Hit enter when complete" -n1 -s
	if [ -e /tmp/database-$PROJECTNAME.php ]; then
		mv /tmp/database-$PROJECTNAME.php $VHOSTS/$DOMAINNAME/httpdocs/app/Config/database.php
	else
		echo "The file /tmp/database-$PROJECTNAME.php was not found."
	fi
fi

#======================================================
# Create the database and user from database.php
#======================================================
if [ -e "$VHOSTS/$DOMAINNAME/httpdocs/app/deployment/create_db_sql.php" ]; then
	if [ -e "$VHOSTS/$DOMAINNAME/httpdocs/app/Config/database.php" ]; then
		read  -p "Create Database and User? y/n"
		if [ "$REPLY" == "y" ]; then
			sudo -u $WEBUSERNAME bash -c "cd $VHOSTS/$DOMAINNAME/httpdocs/app;\
	php deployment/create_db_sql.php | mysql -u root -p\
"
		fi
	else
		echo "Skipping MySQL database and user creation - app/Config/database.php not found."
	fi
else
	echo "Skipping MySQL database and user creation - deployment/create_db_sql.php not found."
fi

#======================================================
# Deploy the schema to the database
#======================================================
if [ -e "$VHOSTS/$DOMAINNAME/httpdocs/app/Config/database.php" ]; then
	read  -p "Setup Database Tables? y/n"
	if [ "$REPLY" == "y" ]; then
		sudo -u $WEBUSERNAME bash -c "cd $VHOSTS/$DOMAINNAME/httpdocs/app;\
Console/cake schema create;\
Console/cake schema update\
"
	fi
else
	echo "Skipping database schema deployment - app/Config/database.php not found."
fi

#======================================================
# reset tmp perms in case any operations have messed it up
#======================================================
chmod -R 777 "$VHOSTS/$DOMAINNAME/httpdocs/app/tmp"
