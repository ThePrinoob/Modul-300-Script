#!/bin/bash

#####################################################
#
# Script: Modul 300
# Autor:  Dominik Ingold, Loris Held, Tobias Rödlach, Jan Schneider, Sven Schüpbach, Patrick Müller
# TODO: netplan DNS change
#
#####################################################

# Parameters
_full=false
_apache_only=false
_bind_only=false
_ftp_only=false

# Print help if no parameter was given
if [ -z "$1" ]; then
    printf "Usage:
-f:         Fully installs and configures bind, apache and ftp
-apache:    Only installs and configures apache
-bind:      Only installs and configures bind
-ftp:       Only installs and configures ftp
"
exit 0
fi

# Parameter stuff
while [ -n "$1" ]
    do
        case "$1" in
            -f) _full=true ;;
            -apache) _apache_only=true ;;
            -bind) _bind_only=true ;;
            -ftp) _ftp_only=true ;;
            *) echo "$1 is not an option. exiting..." ; exit 0 ;
        esac
    shift
done

# Directorys
_bind_dir="/etc/bind"
_zones_dir="$_bind_dir/zones"

# Variables
_netplan_file="/etc/netplan/00-eth0.yaml"

# Bind
_hostname=$(hostname -s) # gets the hostname without the domain
_bind_ip=$(hostname -i | awk '{print $3}') # gets the ip address

_bind_zone=""
declare -A _REVERSE_LINES
declare -a _SUBNETS
declare -a _CNAMES

# Apache
_apache_dir="/etc/apache2"
_apache_conf="$_apache_dir/apache2.conf"
_apache_sites_dir=""
_apache_sites_config="/etc/apache2/sites-available"

# FTP
_ftp_dir="/etc/proftpd"
_ftp_conf="$_ftp_dir/proftpd.conf"

# some nice ascii art :)
cat << "EOF" 
     __  __           _       _   _____  ___   ___            ____            _       _   
    |  \/  | ___   __| |_   _| | |___ / / _ \ / _ \          / ___|  ___ _ __(_)_ __ | |_ 
    | |\/| |/ _ \ / _` | | | | |   |_ \| | | | | | |  _____  \___ \ / __| '__| | '_ \| __|
    | |  | | (_) | (_| | |_| | |  ___) | |_| | |_| | |_____|  ___) | (__| |  | | |_) | |_ 
    |_|  |_|\___/ \__,_|\__,_|_| |____/ \___/ \___/          |____/ \___|_|  |_| .__/ \__|
                                                                             |_|        
EOF

# Update the packages
sudo apt update

# functions
_create_basic_zone () {
    echo '$TTL   3600
@       IN      SOA     '"$_hostname"'.'"$_bind_zone"'. root.'"$_bind_zone"' (
                        1          ; Serial
                        1H         ; Refresh
                        2H         ; Retry
                        1D         ; Expire
                        1H )       ; Negative Cache TTL
;
@       IN      NS      '"$_hostname"'.'"$_bind_zone"'.
' > $1
}

_add_zone () {
    echo 'zone "'"$1"'" {
    type master;
    file "'"$2"'";
};' >> $_bind_dir/named.conf.local
}

_create_site () {
    # $1 is the sitename and path to the directory
    echo '<VirtualHost *:80>
    ServerAdmin admin@smartlearn.ch
    ServerName smartlearn.ch
    ServerAlias www.smartlearn.ch
    DocumentRoot '"$_apache_sites_dir/$1"'
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
' >> "$_apache_sites_config/$1.conf"
}

if [ "$_full" = true ] || [ "$_bind_only" = true ]; then
    printf "Changing the DNS address to $_bind_ip will not be automatically done!\nChange the file $_netplan_file"
    # printf "changing the DNS address to $_bind_ip\n"
    # sed -i 's/addresses: [.*]/addresses: [ '$_bind_ip' ]/' $_netplan_file
    # sed "s/addresses: \[.*/.*\]/addresses: [ $_bind_ip f ]/" $_netplan_file

    # netplan apply

    #####################################################
    #
    # Bind installation and configuration
    #
    #####################################################

    sudo apt install bind9 -y # installs bind

    cat <<EOT > $_bind_dir/named.conf
// This is the primary configuration file for the BIND DNS server named.
//
// Please read /usr/share/doc/bind9/README.Debian.gz for information on the
// structure of BIND configuration files in Debian, *BEFORE* you customize
// this configuration file.
//
// If you are just adding zones, please do that in /etc/bind/named.conf.local

include "/etc/bind/named.conf.options";
include "/etc/bind/named.conf.local";
include "/etc/bind/named.conf.default-zones";
EOT

    cat <<EOT > $_bind_dir/named.conf.local
//
// Do any local configuration here
//

// Consider adding the 1918 zones here, if they are not used in your
// organization
//include "/etc/bind/zones.rfc1918";
EOT

    cat <<EOT > $_bind_dir/named.conf.options
options {
        directory "/var/cache/bind";

        // If there is a firewall between you and nameservers you want
        // to talk to, you may need to fix the firewall to allow multiple
        // ports to talk.  See http://www.kb.cert.org/vuls/id/800113

        // If your ISP provided one or more IP addresses for stable
        // nameservers, you probably want to use them as forwarders.
        // Uncomment the following block, and insert the addresses replacing
        // the all-0's placeholder.

        // forwarders {
        //      0.0.0.0;
        // };

        //========================================================================
        // If BIND logs error messages about the root key being expired,
        // you will need to update your keys.  See https://www.isc.org/bind-keys
        //========================================================================
        dnssec-validation auto;
        listen-on port 53 {
                any;
        };
#       listen-on-v6 { none; };
        recursion yes;                 # enables resursive queries
        allow-recursion {
                localhost;
                127.0.0/8;
                192.168.220.0/24;
                192.168.210.0/24;
        };  # allows recursive queries from "trusted" clients
        allow-query { any; };      # disable zone transfers by default

        forwarders {
                8.8.8.8;
                8.8.4.4;
        };
};
EOT

    printf "creating zones directory in $_bind_dir\n"
    mkdir -p $_zones_dir

    while : ; do
        read -p "Name of the zone, will be the same for the file name (leave blank if no more should be added): " _ZONE
        if [ ! -z "$_ZONE" ]; then
            ##############################
            # Zone
            ##############################

            read -p "First 3 octets of the IP (e.g. 192.168.210): " _ZONE_IP
            read -p "CIDR (e.g. 24): " _ZONE_CIDR

            _SUBNETS=( "$_ZONE_IP.0/$_ZONE_CIDR" )

            # checks if bind zone was set and wont ask again
            if [ -z "$_bind_zone" ]; then
                while : ; do
                    read -p "Is this the zone where the bind server is in it? (y[es] or n[o]): " yn

                    case $yn in
                        [Yy]* ) _bind_zone=$_ZONE; break;;
                        [Nn]* ) _ask_for_zone=true; break;;
                        * ) printf "Please answer yes or no.\n";;
                    esac

                    if [ "$_ask_for_zone" = true ]; then
                        read -p "Whats the zone of the zone then?: " _bind_zone
                    fi
                done
            fi
            _zone_file="$_zones_dir/db.$_ZONE"
            printf "Adding zone $_ZONE\n"

            _add_zone $_ZONE $_zone_file

            _create_basic_zone $_zone_file

            printf "Enter the hostname, ip and then the type for your entry:\n"
            while : ; do
                read -p "Hostname (leave blank if no more should be added): " _HOSTNAME

                if [ -z "$_HOSTNAME" ]; then
                    break;
                fi

                read -p "IP for $_HOSTNAME: " _IP
                read -p "type for $_HOSTNAME (e.g. A, CNAME): " _TYPE
                if [ -z "$_HOSTNAME" ] || [ -z "$_IP" ] || [ -z "$_TYPE" ]; then
                    echo "\nPlease specify everything - try again..."
                    continue
                fi

                echo "$_HOSTNAME       IN      $_TYPE      $_IP" >> "$_zone_file"

                # For every A Record it will automatically create a PTR in the reverse Zone
                if [ $_TYPE == "A" ]; then
                    _REVERSE_LINES=( [$_HOSTNAME]=$_IP )
                fi
            done

            ##############################
            # Reverse Zone
            ##############################
            IFS=. read ip1 ip2 ip3 <<< "$_ZONE_IP" # fills the variables ip1, ip2, ip3 with the octets 

            _zone_file="$_zones_dir/db.$_ZONE_IP"
            _ZONE_REVERSE="$ip3.$ip2.$ip1.in-addr.arpa"

            _add_zone $_ZONE_REVERSE $_zone_file
            _create_basic_zone $_zone_file

            for _HOSTNAME in "${!_REVERSE_LINES[@]}"; do
                IFS=. read ip1 ip2 ip3 ip4 <<< "${_REVERSE_LINES[$_HOSTNAME]}"
                echo "$ip4       IN      PTR      $_HOSTNAME.$_ZONE." >> "$_zone_file"
            done
        else
			echo "Currently it will set: "
			for subnet in "${_SUBNETS[@]}"; do
				echo $subnet
			done
			while : ; do
				read -p "Do you need to add more recursion subnets? (e.g. 192.168.210.0/24) (leave blank if not): " $_SUBNET_TO_ADD
				if [ -z $_SUBNET_TO_ADD ]; then
					_SUBNETS=( "$_SUBNET_TO_ADD" )
				else
					break
				fi
			done
            printf "Adding Subnets to allow-recousion in $_bind_dir/named.conf.options\n"
            _replace_string='allow-recursion {\n                '

            for subnet in "${_SUBNETS[@]}"; do
                IFS=/ read ip cidr <<< "$subnet"
                _replace_string="${_replace_string}${ip}\/${cidr};\n                "
            done
            _replace_string="${_replace_string}/"
            sed -i "s/allow-recursion {.*/$_replace_string" "$_bind_dir/named.conf.options"
            
            printf "alright the zones should be set now :)\n"
            break
        fi
    done

    sudo systemctl restart bind9
    printf "Restarted bind!"
fi

printf "\n\n"

#####################################################
#
# Apache2 installation and configuration
#
#####################################################

if [ "$_full" = true ] || [ "$_apache_only" = true ]; then

    sudo apt install apache2 -y

    read -p "Enter the full directory where all the website should be stored (e.g. /www): " _apache_sites_dir

    mkdir -p $_apache_sites_dir

    sudo chmod -R 770 $_apache_sites_dir

    sudo a2dissite 000-default.conf
    printf "Disabled default site\n"

    echo '<Directory '"$_apache_sites_dir"'/>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
</Directory>' >> $_apache_conf

    printf "Added $_apache_sites_dir to $_apache_conf\n"

    while : ; do
        read -p "Enter the name for the Website, needs to be the same as the file name in $_apache_sites_dir/ (e.g. www.smartlearn.dmz) (leave blank if no more should be set): " _WEBSITE_NAME
        if [ ! -z "$_WEBSITE_NAME" ]; then
            _create_site $_WEBSITE_NAME
            printf "$_WEBSITE_NAME config file has been created!\n"

            IFS=. read _CNAME <<< $_WEBSITE_NAME
            _CNAMES=( "$_CNAME" )

            sudo a2ensite "$_WEBSITE_NAME.conf"
            printf "$_WEBSITE_NAME has been enabled!\n"
        else
            printf "alright the websites should be set now :)\n"
            break
        fi
    done

    if [ "$_full" = true ] || [ "$_bind_only" = true ]; then
        for cname in "${_CNAMES[@]}"; do
            read -p "To which config file should the cname $cname be added (e.g. db.smartlearn.dmz): " _FILE
            echo "$cname    IN       CNAME      $_hostname" >> "$_zones_dir/$_FILE"
        done
        sudo systemctl restart bind9
        printf "Restarted bind!\n"
    else 
        printf "Please define the following string(s) in the zones file on the bind server\n"
        for cname in "${_CNAMES[@]}"; do
            echo "$cname    IN       CNAME      $_hostname"
        done
    fi
    sudo systemctl restart apache2
    printf "Restarted apache2"
fi

printf "\n\n"

#####################################################
#
# FTP installation and configuration
#
#####################################################

if [ "$_full" = true ] || [ "$_ftp_only" = true ]; then
    sudo apt install proftpd -y

    read -p "Enter the username for the ftpuser (e.g. ftpuser): " _ftp_user
    read -p "Enter the full directory where home folder for the ftpuser should be stored (e.g. /www): " _ftp_home
    read -p "Enter the default root directory (e.g. /www/www.smartlearn.dmz/): " _ftp_default_root

    echo 'DefaultRoot '"$_ftp_default_root"'
UseIPv6 off
AuthOrder mod_auth_file.c
AuthUserFile /etc/proftpd/ftpd.passwd
AuthPam off
RequireValidShell off
' >> $_ftp_conf

    sudo service proftpd restart
    printf "Restarting proftp\n"

    ftpasswd --passwd --file="$_ftp_dir/ftpd.passwd" --name="$_ftp_user" --uid=1001 --home="$_ftp_home" --shell=/bin/false

    read -p "Specify a CNAME for your FTP server (leave blank if you dont need one): " _CNAME

    if [ -n "$_CNAME" ]; then
        if [ "$_full" = true ] || [ "$_bind_only" = true ]; then
            read -p "To which config file should the cname $_CNAME be added (e.g. www.smartlearn.dmz): " _FILE
            echo "$_CNAME    IN       CNAME      $_hostname" >> "$_zones_dir/$_FILE"
            sudo systemctl restart bind9
            printf "Restarted bind!\n"
        else 
            printf "Please define the following string(s) in the zones file on the bind server\n"
            echo "$_CNAME    IN       CNAME      $_hostname"
        fi
    fi

    sudo service proftpd restart
    printf "Restarting proftp"
fi

printf "\n\n"