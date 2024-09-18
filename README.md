# Plugin Bulletins Creator

This plugin is intended to create bulletins dynamically



# Requirements

- Koha mininum version: 18.11
- Perl modules:
    - Text::CSV::Encoded
    - Text::Truncate



# Installation

Download the package file BulletinsCreator.kpz

Login to Koha Admin and go to the plugin screen

Upload Plugin



# Configuration

In the configuration page, you can:

- Set the number of items per bulletin. Multiple values ​​can be entered separated by ",". Default: 10,20,30,40,50

- Set the number of items per carousel. Multiple values ​​can be entered separated by ",". Default: 5,10,15,20,25,30

- Set the number of bulletins of type search per library. Single value, default: 5

- Set the number of bulletins of type static per library. Single value, default: 5

- Set SQL query to get most issued records

- Set the SQL query to get news of records

- Set the SQL query to get news of items

- Set the route type. Options: PLACK or CGI

    - To configure the PLACK routes you must modify the opac.psgi file and add the following code:
    my $plugin_bulletins = Plack::App::CGIBin->new( root => '/var/opt/koha-upsa/var/lib/plugins/Koha/Plugin/Es/Xercode/BulletinsCreator/opac/' );
    mount '/bulletins' => $plugin_bulletins;

- Set the size and marker from which the author's text will be truncated. Default: (size:20),(marker:...)

- Set the size and marker from which the title text will be truncated. Default: (size:25),(marker:...)

- Set the size and marker from which the item information text will be truncated. Default: (size:300),(marker:...)



# Documentation

Run the tool, it will allow you to:

- Search for bulletins by both individual libraries and groups of libraries.
    
    - Note 1: Initially when the plugin is installed you will only find the option to search by individual library, but the moment you create a bulletin belonging to a group, the option to search by library groups will also be displayed.

    - Note 2: You only can select a individual library or a group, never both at the same time


- Bulletins creation/edition

    - Once a bulletin has been created, and if it isn't of STATIC type (in which the content is entered manually), a scheduled task (misc/build_bulletins.pl) will have to be executed to generate the content of the bulletins.

    - build_bulletins.pl

        - Parameters:
            
            - (-b) followed by the library code or * (all libraries)
                
                - The bulletins of the indicated library will be regenerated
                
                - Example: KOHA_CONF="/usr/share/koha-saas-update-dev/etc/koha-conf.xml" PERL5LIB="/home/nuria/workspace/koha-saas-update" perl build_bulletins.pl -b *

            - (-e) followed by a library code, or a list of library codes (separated by ",")
                
                - The library(s) passed as a parameter will be ignored, while the bulletins of the other libraries will be regenerated.
                
                - Example: KOHA_CONF="/usr/share/koha-saas-update-dev/etc/koha-conf.xml" PERL5LIB="/home/nuria/workspace/koha-saas-update" perl build_bulletins.pl -e BCN,NYK,ALC



# Api

You can get the bulletins data through an api. Possible options:

- Get bulletins of a specific library

    - Structure: ROUTE/api/v1/contrib/bulletinscreator/bulletins/LIBRARY_CODE
    - Example: http://11.0.40.37:8282/api/v1/contrib/bulletinscreator/bulletins/BCN

- Get bulletins from ALL libraries

    - Structure: ROUTE/api/v1/contrib/bulletinscreator/bulletins/*
    - Example: http://11.0.40.37:8282/api/v1/contrib/bulletinscreator/bulletin/*

- Get a specific bulletin

    - Structure: ROUTE/api/v1/contrib/bulletinscreator/bulletin/BULLETIN_ID
    - Example: http://11.0.40.37:8282/api/v1/contrib/bulletinscreator/bulletin/5
