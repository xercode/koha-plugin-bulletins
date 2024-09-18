#!/usr/bin/perl
#
# Copyright (C) 2020 Xercode
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# Koha; if not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307 USA


use strict;
use CGI;
use C4::Context;
use C4::Search;
use C4::Output;
use C4::Koha;
use C4::Biblio;
use Date::Manip;
use Koha::Libraries;
use Data::Dumper;
use LWP::UserAgent;
use XML::Parser;
use Getopt::Long;
use JSON;
use Encode;
use IO::Socket::SSL qw( SSL_VERIFY_NONE );
use Koha::Plugin::Es::Xercode::BulletinsCreator::bulletins::BulletinsFunctions;
use Koha::Plugin::Es::Xercode::BulletinsCreator;

=head1 NAME

Script to build table carousel_last_biblios with the last items arrived at Koha
The bulletins of the library indicated with -b are regenerated (* refers to all libraries)
If you pass an ignore with a list of libraries, those libraries will be ignored and the bulletins for the other libraries will be regenerated

=head1 DESCRIPTION

=over 2

=cut

my ($branch,$ignore,$verbose);

GetOptions(
   'b:s' => \$branch,
   'e:s' => \$ignore,
   'v'   => \$verbose,
   );


if ($branch && $ignore) {
	warn "No puedes usar los dos parámetros a la vez, escoge -b o -e \n";
	exit();
}

my $dbh = C4::Context->dbh;

my $plugin_self = Koha::Plugin::Es::Xercode::BulletinsCreator->new(); #Actua como el $self para pasarselo a las funciones
my $table_bulletins = $plugin_self->get_qualified_table_name('bulletins');
my $table_contents = $plugin_self->get_qualified_table_name('bulletins_contents');

my %settings = GetBulletinSettings($plugin_self); 

my $dbh = C4::Context->dbh;
my $sql = "SELECT * FROM `$table_bulletins` WHERE type <> 'LIST'";

if ($branch) {
	$branch =~ s/,/','/g;
	$sql .= " AND branchcode IN ('$branch') "; 
}

if ($ignore) {
	$ignore =~ s/,/','/g;
	$sql .= " AND branchcode NOT IN ('$ignore') "; 
}

my $sth = $dbh->prepare($sql);
$sth->execute();

while (my $row = $sth->fetchrow_hashref){

	my $id = $row->{'idBulletin'};
	my $type = $row->{'type'};
	my $branchcode = $row->{'branchcode'};
	my $value = $row->{'value'};
	my $elementsInBulletin = $row->{'elementsInBulletin'};
	my $elementsInCarousel = $row->{'elementsInCarousel'};
	my $days = $row->{'days'};
	my $_bulletinName = from_json($row->{'name'}); 
	my $name = $_bulletinName->{'gl'}; 
	$name = Encode::encode("utf8", $name);
	my $filter = $row->{'filter'};

	my $limit = $elementsInBulletin;
	if ($elementsInBulletin < $elementsInCarousel) {
		$limit = $elementsInCarousel;
	}

	my %params;
	$params{'bulletinid'} = $id;

	my $libraryname;

	if($branchcode eq '*'){
		$libraryname = "Red de bibliotecas";
	} else {

		my $library = Koha::Libraries->find($branchcode);
		if ($library) {
			$libraryname = Encode::encode("utf8",$library->branchname);
		} else{
			my $search_group = Koha::Library::Groups->find( $branchcode );
			if ($search_group) {
				$libraryname = Encode::encode("utf8",$search_group->description);
			}
		}
	}

	warn "\nBoletin ".$name.'('.$id.") de tipo ".$type." de ".$libraryname." (".$branchcode.")\n";

	my @hidden = GetBulletinHiddenContent($plugin_self, $id); 
	my $hiddenItems = scalar @hidden;

	warn "\tEliminamos o contido do boletin numero ".$id."\n";
	my $sthDel=$dbh->prepare("DELETE FROM `$table_contents` WHERE bulletinid = ? ");
	$sthDel->execute($id);

	if ($type eq 'TOPISSUES') {
		
		my $sql = $settings{'SqlMostIssues'};
		if($verbose){
			warn "\n\tSqlMostIssues => ".$sql."\n\n";
		}

		unless ($sql) {
			warn "Revisar configuracion de boletins SqlMostIssues ";
			exit;
		}

		if ($days) {
			$sql =~ s/365/$days/g;
		}

		#Partimos por GROUP BY para añadir la condición
		my ($sql1,$groupBy) = split /GROUP BY/, $sql;

		if ($branchcode ne '*') {
			my $search_group = Koha::Library::Groups->find( $branchcode );
			if($search_group){
				my @branchcodes = map { $_->branchcode } $search_group->all_libraries;
        		@branchcodes = sort { $a cmp $b } @branchcodes;
        		my $branchStr = join("','",@branchcodes);
        		$sql1 .= " AND s.branch IN ('$branchStr') ";
			} else {
				$sql1 .= " AND s.branch = '$branchcode' ";
			}
		}

		if ($limit) {
			$groupBy .= " LIMIT $limit ";
		}

		$sql = $sql1.' GROUP BY '.$groupBy;

		if($verbose){
			warn "\tEjecutamos => ".$sql."\n\n";
		}

		my $sth = $dbh->prepare($sql);
		$sth->execute();

		my %bulletinContent;

		while (my $row = $sth->fetchrow_hashref) {
			my $biblionumber = $row->{'biblionumber'};
			$params{'biblionumber'} = $biblionumber;
			%params = CompleteParams($plugin_self, %params); 

			#Comprobamos si está oculto en el OPAC
			my $hiddenInOpac = IsHiddenInOpac($biblionumber); 
			if ($hiddenInOpac) {
            warn "\tRexistro ".$biblionumber." oculto no OPAC \n";
            next;
         }

			#Detectamos duplicados
			if ($bulletinContent{$biblionumber}) {
				next;
			}

			if ($id && $biblionumber) {
				warn "\tBoletin $id: Rexistro $biblionumber Préstamos ".$row->{'tot'}."\n";
				AddToBulletin($plugin_self, %params);
				$bulletinContent{$biblionumber} = $biblionumber;
			}
		}

	} elsif($type eq 'LASTBIBLIOS'){

		my $sql;

		if($value eq 'item'){
			$sql = $settings{'SqlNewItems'};
			if($verbose){
				warn "\n\tSqlNewItems => ".$sql."\n\n";
			}
			if ($days) {
				$sql =~ s/1 YEAR/$days DAY/g;
				$sql =~ s/YEAR\(/DATE(/g;
			}

		} elsif($value eq 'biblio'){
			$sql = $settings{'SqlNewBiblios'};
			if($verbose){
				warn "\n\tSqlNewBiblios => ".$sql."\n\n";
			}
			if ($days) {
				$sql =~ s/1 YEAR/$days DAY/g;
				$sql =~ s/AND EXTRACTVALUE/AND DATE(datecreated) >= DATE(DATE_SUB(CURDATE(),INTERVAL $days DAY)) AND DATE(datecreated)<= DATE(CURDATE()) AND EXTRACTVALUE/g;
			}
		}

		unless ($sql) {
			warn "Revisar configuracions de boletins SqlNewItems e SqlNewBiblios ";
			exit;
		}

		my ($sql1,$groupBy) = split /GROUP BY/, $sql;

		if ($branchcode ne '*') {
			my $search_group = Koha::Library::Groups->find( $branchcode );
			if($search_group){
				my @branchcodes = map { $_->branchcode } $search_group->all_libraries;
        		@branchcodes = sort { $a cmp $b } @branchcodes;
        		my $branchStr = join("','",@branchcodes);
        		$sql1 .= " AND homebranch IN ('$branchStr') ";
			} else {
				$sql1 .= " AND homebranch = '$branchcode' ";
			}
		}

		if ($filter) {
			my @filters = split /,/,$filter;
			foreach my $f (@filters){
				my $_json = from_json($f);
	            my %json = %$_json;
	            foreach my $key (keys %json){
	            	my $value = trim($json{$key});
	            	$sql1 .= " AND ( $key IS NULL OR $key <> '$value' )";
	            }
	        }
		}

		if ($limit) {
			$groupBy .= " LIMIT $limit ";
		}

		$sql = $sql1.' GROUP BY '.$groupBy;

		if($verbose){
			warn "\tEjecutamos => ".$sql."\n\n";
		}

		my $sth = $dbh->prepare($sql);
		$sth->execute();

		my %bulletinContent;

		while (my $row = $sth->fetchrow_hashref) {
			my $biblionumber = $row->{'biblionumber'};
			$params{'biblionumber'} = $biblionumber;
			%params = CompleteParams($plugin_self, %params);

			my $dateaccessioned = $row->{'max_dateaccessioned'};
			unless($dateaccessioned){
				$dateaccessioned = ' ';
			}

			my $hiddenInOpac = IsHiddenInOpac($biblionumber);
			if ($hiddenInOpac) {
                warn "\tRexistro ".$biblionumber." oculto no OPAC \n";
                next;
            }

			if ($bulletinContent{$biblionumber}) {
				next;
			}			

			if ($id && $biblionumber) {
				warn "\tBoletin $id: Rexistro $biblionumber $dateaccessioned\n";
				AddToBulletin($plugin_self, %params);
				$bulletinContent{$biblionumber} = $biblionumber;
			}
		}

	} elsif($type eq 'SEARCH'){

		#Leemos el feed de la consulta
		my $url = $value.'&format=rss2&count='.$limit;
		my $agent = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0 , SSL_verify_mode => SSL_VERIFY_NONE, }, ); # Create me a browser
		$agent->agent("OPAC Query"); # Set the browser name
		my $req = HTTP::Request->new(GET => ($url)); # Set up the request we'll run
		my $res = $agent->request($req); # Run the request
		my $page = $res -> content();
		$page =~ s/&q/&amp;q/g;
		$page =~ s/&limit/&amp;limit/g;
		$page =~ s/&idx/&amp;idx/g;

		#Buscamos los enlaces a los bibliograficos de los resultados y extraemos los biblionumbers
        my $xml;

        my $err = eval {
        	$xml = XML::LibXML->load_xml(string => $page);
        };

        if ( $@ ) {
        	warn "    El boletin $name no tiene una url correcta \n";
        	next;
        };

        my @links = $xml->getElementsByTagName("link");

        my %bulletinContent;

		foreach my $link (@links){
			my $linkString = $link->toString;
			$linkString =~ s/<link>//g;
			$linkString =~ s/<\/link>//g;

			if (index($linkString,'biblionumber=') != -1) {
				my ($url, $biblionumber) = split("biblionumber=", $linkString);
				$params{'biblionumber'} = $biblionumber;
				%params = CompleteParams($plugin_self, %params);

				my $hiddenInOpac = IsHiddenInOpac($biblionumber);
				if ($hiddenInOpac) {
	                warn '		Rexistro '.$biblionumber." oculto no OPAC \n";
	                next;
	            }

				if ($bulletinContent{$biblionumber}) {
					next;
				}

				if ($id && $biblionumber) {
					warn "    Boletin $id: Rexistro $biblionumber \n";
					AddToBulletin($plugin_self, %params);
					$bulletinContent{$biblionumber} = $biblionumber;
				}
			}

		}
	}

	#Volvemos a ocultar los que estaban marcados como ocultos
	if ($hiddenItems > 0) {
		my $tohide = join(',',@hidden);
		$dbh->do("UPDATE `$table_contents` SET hidden = 1 WHERE bulletinid = $id AND biblionumber IN ($tohide)");
	}

}

sub trim {
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}
