#####################################################################################
# Copyright 2014 Normation SAS
#####################################################################################
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, Version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#####################################################################################

# This file contains bundles to manage password between all components of a
# Rudder server (OpenLDAP, PostgreSQL, Apache WebDAV, endpoint and web interface)

# It is currently only used on root servers where all components are installed
# on one host. It may be extended in the future to support changing passwords
# across multiple hosts.

bundle common p
{

  vars:

    root_server::

      "no" int => getfields("RUDDER_PSQL_PASSWORD:.*","/opt/rudder/etc/rudder-passwords.conf",":","psql_password");
      "no2" int => getfields("RUDDER_OPENLDAP_BIND_PASSWORD:.*","/opt/rudder/etc/rudder-passwords.conf",":","ldap_password");

      "properties_files" slist => { "${g.rudder_base}/etc/rudder-web.properties", "${g.rudder_base}/etc/inventory-web.properties" };
      "managed_files" slist => { "@{properties_files}", "/root/.pgpass", "${g.rudder_base}/etc/openldap/slapd.conf" };

}

bundle agent root_password_check_disclaimer
{

  vars:

      "disclaim" slist => { "@{p.managed_files}" };

  files:

    root_server::

      "${disclaim}"
        edit_line => insert_rudder_disclaimer,
        comment => "Insert a disclaimer into Rudder";

}

bundle agent root_password_check_file
{

  vars:

      "pgpass[1]" string => "localhost";
      "pgpass[2]" string => "5432";
      "pgpass[3]" string => "rudder";
      "pgpass[4]" string => "rudder";
      "pgpass[5]" string => "${p.psql_password[2]}";

  files:

    root_server::

      "${g.rudder_base}/etc/rudder-passwords.conf"
        perms => mog("600", "root", "root"),
        classes => kept_if_else("file_ok", "file_repaired", "file_error");

      "/root/.pgpass"
        create    => "true",
        edit_line => root_password_check_file_pgpass("root_password_check_file.pgpass");

  reports:

    root_server::

      "@@server-roles@@result_success@@&TRACKINGKEY&@@Check rudder-passwords.conf and pgpass files@@None@@${g.execRun}##${g.uuid}@#The Rudder passwords file is present and secure"
        ifvarclass => "file_ok.!file_repaired.!file_error";

      "@@server-roles@@result_repaired@@&TRACKINGKEY&@@Check rudder-passwords.conf and pgpass files@@None@@${g.execRun}##${g.uuid}@#The Rudder passwords file permissions were fixed"
        ifvarclass => "file_repaired.!file_error";

      "@@server-roles@@result_error@@&TRACKINGKEY&@@Check rudder-passwords.conf and pgpass files@@None@@${g.execRun}##${g.uuid}@#EMERGENCY: THE ${g.rudder_base}/etc/rudder-passwords.conf FILE IS *ABSENT*. THIS RUDDER SERVER WILL *NOT* OPERATE CORRECTLY."
        ifvarclass => "file_error";

    policy_server.!root_server::

      "@@server-roles@@result_success@@&TRACKINGKEY&@@Check rudder-passwords.conf and pgpass files@@None@@${g.execRun}##${g.uuid}@#The Rudder passwords file does not need to be checked on relay servers. Skipping...";

}

bundle agent root_password_check_ldap
{

  vars:

      # Build an array using ldap configuration values

      "rudder[ldap.authpw]" string => "${p.ldap_password[2]}";

      "slapd[rootpw]" string => "${p.ldap_password[2]}"; # Looks like a bug, I can not use execresult("/opt/rudder/sbin/slappasswd -s ${p.ldap_password[2]}","noshell");

      "prop_edit" slist => { "@{p.properties_files}" };

  files:

    root_server::

      "${prop_edit}"
        edit_line => set_variable_values("root_password_check_ldap.rudder"),
        classes => kept_if_else("rudder_web_password_integrity_ok", "rudder_web_password_integrity_changed", "rudder_web_password_integrity_failed"),
        comment => "Verifying the Rudder Webapp properties file passwords and users";

      "${g.rudder_base}/etc/openldap/slapd.conf"
        edit_line => update_slapd("root_password_check_ldap.slapd"),
        classes => kept_if_else("rudder_ldap_password_integrity_ok", "rudder_ldap_password_integrity_changed", "rudder_ldap_password_integrity_failed"),
        comment => "Verifying the Rudder LDAP file password and user";

  commands:

    rudder_ldap_password_integrity_changed::

      "/etc/init.d/rudder-slapd restart"
        contain => in_shell,
        classes => if_else("slapd_restarted", "slapd_restart_failed");

  reports:

    root_server::

      "@@server-roles@@result_success@@&TRACKINGKEY&@@Check LDAP in rudder-webapp.properties@@None@@${g.execRun}##${g.uuid}@#The Rudder Webapp configuration files are OK (checked LDAP password)"
        ifvarclass => "rudder_web_password_integrity_ok.!rudder_web_password_integrity_changed.!rudder_web_password_integrity_failed";

      "@@server-roles@@result_repaired@@&TRACKINGKEY&@@Check LDAP in rudder-webapp.properties@@None@@${g.execRun}##${g.uuid}@#The Rudder Webapp configuration files were updated with a new LDAP password"
        ifvarclass => "rudder_web_password_integrity_changed.!rudder_web_password_integrity_failed";

      "@@server-roles@@result_error@@&TRACKINGKEY&@@Check LDAP in rudder-webapp.properties@@None@@${g.execRun}##${g.uuid}@#The Rudder Webapp configuration files could not be updated to set the LDAP password"
        ifvarclass => "rudder_web_password_integrity_failed";

      "@@server-roles@@result_success@@&TRACKINGKEY&@@Check LDAP credentials@@None@@${g.execRun}##${g.uuid}@#The OpenLDAP configuration file is OK (checked rootdn password)"
        ifvarclass => "rudder_ldap_password_integrity_ok.!rudder_ldap_password_integrity_changed.!rudder_ldap_password_integrity_failed";

      "@@server-roles@@result_repaired@@&TRACKINGKEY&@@Check LDAP credentials@@None@@${g.execRun}##${g.uuid}@#The OpenLDAP configuration file was updated with a new rootdn password"
        ifvarclass => "rudder_ldap_password_integrity_changed.!rudder_ldap_password_integrity_failed";

      "@@server-roles@@result_error@@&TRACKINGKEY&@@Check LDAP credentials@@None@@${g.execRun}##${g.uuid}@#The OpenLDAP configuration file could not be updated to set the rootdn password"
        ifvarclass => "rudder_ldap_password_integrity_failed";

      "@@server-roles@@log_info@@&TRACKINGKEY&@@Check rudder-passwords.conf file@@None@@${g.execRun}##${g.uuid}@#rudder-slapd has been restarted"
        ifvarclass => "slapd_restarted";

    policy_server.!root_server::

      "@@server-roles@@result_success@@&TRACKINGKEY&@@Check LDAP in rudder-webapp.properties@@None@@${g.execRun}##${g.uuid}@#The Rudder Webapp configuration files do not need to be checked on relay servers. Skipping...";

      "@@server-roles@@result_success@@&TRACKINGKEY&@@Check LDAP credentials@@None@@${g.execRun}##${g.uuid}@#The OpenLDAP configuration file do not need to be checked on relay servers. Skipping...";

}

bundle agent root_password_check_psql
{

  vars:

    root_server::

      "no" int => getfields("RUDDER_PSQL_PASSWORD:.*","/opt/rudder/etc/rudder-passwords.conf",":","psql_pass");

      # Build an array using PSQL configuration values
      "rudder[rudder.jdbc.password]" string => "${p.psql_password[2]}";

  classes:

    root_server::

      "psql_cant_connect" not => returnszero("/usr/bin/psql --host localhost --username rudder --dbname rudder --quiet --output /dev/null --command 'select 1' 2> /dev/null","useshell");

  files:

    root_server::

      "${g.rudder_base}/etc/rudder-web.properties"
        edit_line => set_variable_values("root_password_check_psql.rudder"),
        classes => kept_if_else("rudder_web_password_integrity_ok", "rudder_web_password_integrity_changed", "rudder_web_password_integrity_failed"),
        comment => "Verifying the Rudder Webapp properties file passwords and users";

  commands:

    psql_cant_connect::

      "/usr/bin/psql -q -c \"ALTER USER rudder WITH PASSWORD '${p.psql_password[2]}'\""
        contain => setuid_sh("postgres"),
        classes => if_else("postgres_updated", "postgres_update_failed");

  reports:

    root_server::

      "@@server-roles@@result_success@@&TRACKINGKEY&@@Check SQL in rudder-webapp.properties@@None@@${g.execRun}##${g.uuid}@#The Rudder Webapp configuration files are OK (checked SQL password)"
        ifvarclass => "rudder_web_password_integrity_ok.!rudder_web_password_integrity_changed.!rudder_web_password_integrity_failed";

      "@@server-roles@@result_repaired@@&TRACKINGKEY&@@Check SQL in rudder-webapp.properties@@None@@${g.execRun}##${g.uuid}@#The Rudder Webapp configuration files were updated with a new SQL password"
        ifvarclass => "rudder_web_password_integrity_changed.!rudder_web_password_integrity_failed";

      "@@server-roles@@result_error@@&TRACKINGKEY&@@Check SQL in rudder-webapp.properties@@None@@${g.execRun}##${g.uuid}@#The Rudder Webapp configuration files could not be updated to set the SQL password"
        ifvarclass => "rudder_web_password_integrity_failed";

      "@@server-roles@@result_success@@&TRACKINGKEY&@@Check SQL credentials@@None@@${g.execRun}##${g.uuid}@#The Rudder PostgreSQL user account's password is correct and works"
        ifvarclass => "!psql_cant_connect";

      "@@server-roles@@result_repaired@@&TRACKINGKEY&@@Check SQL credentials@@None@@${g.execRun}##${g.uuid}@#The Rudder PostgreSQL user account's password has been changed"
        ifvarclass => "postgres_updated";

      "@@server-roles@@result_error@@&TRACKINGKEY&@@Check SQL credentials@@None@@${g.execRun}##${g.uuid}@#The Rudder PostgreSQL user account's password could not be changed!"
        ifvarclass => "postgres_update_failed";

    policy_server.!root_server::

      "@@server-roles@@result_success@@&TRACKINGKEY&@@Check SQL in rudder-webapp.properties@@None@@${g.execRun}##${g.uuid}@#The Rudder Webapp configuration files do not need to be checked on relay servers. Skipping...";

      "@@server-roles@@result_success@@&TRACKINGKEY&@@Check SQL credentials@@None@@${g.execRun}##${g.uuid}@#The Rudder PostgreSQL user account's do not need to be checked on relay servers. Skipping...";

}

bundle agent root_password_restart_jetty
{

  commands:

    rudder_web_password_integrity_changed::

      "/etc/init.d/rudder-jetty restart </dev/null >/dev/null 2>/dev/null"
        contain => in_shell,
        classes => if_else("jetty_restarted", "jetty_restart_failed");

  reports:

      "@@server-roles@@log_info@@&TRACKINGKEY&@@Check rudder-webapp.properties@@None@@${g.execRun}##${g.uuid}@#Jetty has been restarted"
        ifvarclass => "jetty_restarted";


}

bundle agent root_password_check_dav
{

  vars:

    debian::
      "webdav_check_wwwgroup" string => "www-data";

    redhat::
      "webdav_check_wwwgroup" string => "apache";

    !debian.!redhat::
      "webdav_check_wwwgroup" string => "www";

    SuSE::
      "htpasswd_bin" string => "/usr/bin/htpasswd2";

    !SuSE::
      "htpasswd_bin" string => "/usr/bin/htpasswd";

  classes:

      "dav_cant_connect" not => returnszero("/usr/bin/curl -s -f -u ${g.davuser}:${g.davpw} -T /etc/motd http://localhost/inventory-updates/motd","noshell");


  files:

      "${g.rudder_base}/etc/htpasswd-webdav"
        create => "true",
        perms => mog("640", "root", "${webdav_check_wwwgroup}");

  commands:

    dav_cant_connect::

      # Apache reads this file when it's changed, no need to restart or reload it after it's changed
      "${htpasswd_bin}"
        args => "-b ${g.rudder_base}/etc/htpasswd-webdav ${g.davuser} ${g.davpw}",
        classes => kept_if_else("rudder_apache_davpassword_ok", "rudder_apache_davpassword_changed", "rudder_apache_davpassword_failed"),
        comment => "Repairing the Rudder WebDAV user and password";

  reports:

    cfengine::

      "@@server-roles@@result_success@@&TRACKINGKEY&@@Check WebDAV credentials@@None@@${g.execRun}##${g.uuid}@#The Rudder WebDAV user and password are OK"
        ifvarclass => "!dav_cant_connect";

      "@@server-roles@@result_repaired@@&TRACKINGKEY&@@Check WebDAV credentials@@None@@${g.execRun}##${g.uuid}@#The Rudder WebDAV user and password were updated"
        ifvarclass => "rudder_apache_davpassword_changed.!rudder_apache_davpassword_failed";

      "@@server-roles@@result_error@@&TRACKINGKEY&@@Check WebDAV credentials@@None@@${g.execRun}##${g.uuid}@#The Rudder WebDAV user and password could not be updated"
        ifvarclass => "rudder_apache_davpassword_failed";

}

bundle edit_line update_slapd(tab)
{

  vars:

      "index" slist => getindices("${tab}");

  delete_lines:

      "${index}.*";

  insert_lines:

      "${index}		${${tab}[${index}]}" location => after("^rootdn.*");

}

bundle edit_line root_password_check_file_pgpass(parameter)
{
  vars:

      "indices" slist => getindices(${parameter});

  insert_lines:

      "localhost:5432:rudder:${${parameter}[4]}:${${parameter}[5]}";

  field_edits:

      "localhost:5432:rudder:.*"

    # Set field of the file to parameter
        edit_field => col(":","${indices}","${${parameter}[${indices}]}","set");

}
