#!/usr/bin/perl

# This file is part of Koha.
#
# Parts Copyright (C) 2020 Juan F. Romay Sieira
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.


use Modern::Perl;
use CGI qw ( -utf8 );
use C4::Auth qw(get_template_and_user);
use C4::Output qw(output_html_with_http_headers);
use C4::Languages qw(getTranslatedLanguages accept_language);
use Koha::Plugin::Es::Xercode::BulletinsCreator::bulletins::BulletinsFunctions;
use Koha::Plugin::Es::Xercode::BulletinsCreator;
use C4::Biblio;
use JSON;
use List::MoreUtils qw/uniq/;
use Cwd qw( abs_path );
use File::Basename qw( dirname );
use Koha::Library::Groups;
use Koha::Template::Plugin::AuthorisedValues;

my $cgi = new CGI;
my $dbh   = C4::Context->dbh;

my $plugin_self = Koha::Plugin::Es::Xercode::BulletinsCreator->new(); #Actua como el $self para pasarselo a las funciones

my $pluginDir = dirname(abs_path($0));

#Set template according to language
my $lang = C4::Languages::getlanguage($cgi);
my $template_name;

if ($lang eq 'es-ES') {
    $template_name = "$pluginDir/opac-bulletin_es-ES.tt";
} elsif ($lang eq 'gl') {
    $template_name = "$pluginDir/opac-bulletin_gl.tt";
} else {
    $template_name = "$pluginDir/opac-bulletin_en.tt";
}

my ( $template, $borrowernumber, $cookie ) = get_template_and_user(
    {
        template_name   => $template_name,
        type            => "opac",
        query           => $cgi,
        authnotrequired => ( C4::Context->preference("OpacPublic") ? 1 : 0 ),
    }
);

my $homebranch;
if (C4::Context->userenv) {
    $homebranch = C4::Context->userenv->{'branch'};
}
if (defined $cgi->param('branch') and length $cgi->param('branch')) {
    $homebranch = $cgi->param('branch');
}
elsif (C4::Context->userenv and defined $cgi->param('branch') and length $cgi->param('branch') == 0 ){ 
    $homebranch = "";
}

my $bulletinid = $cgi->param('id'); 
my $forcedAudience = $cgi->param('audience');
my $export = $cgi->param('export');
my $bulletin = GetBulletinInfo($plugin_self,$bulletinid);
my $library = Koha::Libraries->find($bulletin->{branchcode});
my $branchName;
if($library){
    $branchName = $library->branchname;
} else {
    my $search_group = Koha::Library::Groups->find( $bulletin->{branchcode} );
    if ($search_group) {
        $branchName = $search_group->description;
    } else {
        $branchName = C4::Context->preference('LibraryName')
    }
}

my $catalogUrl = C4::Context->preference('OPACBaseURL');


if ($export && ($export ne "rtf" && $export ne "html")){
    $export = 0;
}

if ($forcedAudience && $forcedAudience ne ""){
    my $_fixedJSON = '[{"format":[""]},{"audience":["'.$forcedAudience.'"]},{"language":[""]},{"genre":[""]},{"year":[""]}]';
    $template->param('fixedJSON', $_fixedJSON);
}

if ($bulletin && $bulletin->{enabled}){
    my $permissionOnThisBulletin = 1;
        
    if ($bulletin->{branchcode} ne "*" && $bulletin->{type} ne "LASTBIBLIOS" && $bulletin->{type} ne "TOPISSUES" ){
        $permissionOnThisBulletin = 0;
    }

    if ($bulletin->{branchcode} ne "*" && $homebranch && $bulletin->{branchcode} eq $homebranch ){
        $permissionOnThisBulletin = 1;
    }
    
    if($bulletin->{type} eq "LASTBIBLIOS" || $bulletin->{type} eq "TOPISSUES"){
        $template->param( 'topissues_lastbiblios' => 1 );
    }

    if ($permissionOnThisBulletin){
        unless ($export){
            my $iteminfo_branchcode = undef;
            $iteminfo_branchcode = $bulletin->{branchcode} if ($bulletin->{itemInfo});
            my $_bulletinContents = GetBulletinContents($plugin_self, $bulletin->{idBulletin}, 1, 0, $iteminfo_branchcode, 1);
            my $_bulletinName = from_json($bulletin->{'name'});
            my $_bulletinDescription = from_json($bulletin->{'description'});
            my $content = {
                'id' =>, $bulletin->{idBulletin},
                'name' =>, $_bulletinName->{$lang},
                'description' =>, $_bulletinDescription->{$lang},
                'iteminfo' => ($bulletin->{itemInfo})?\1:\0,
                'contents' => \@$_bulletinContents
            };

            if (($bulletin->{type} eq "LASTBIBLIOS" || $bulletin->{type} eq "TOPISSUES") && C4::Context->userenv){
                # Search for other bulletins in other libraries of the same type, to change in a select
                my $otherbulletins = GetBulletinsOfType($plugin_self, $bulletin->{type});
                my @otherlibraries;
                foreach (@$otherbulletins){
                    next if ($_->{idBulletin} eq $bulletin->{idBulletin});
                    my $totalElements = GetBulletinContentsCount($plugin_self, $_->{'idBulletin'});
                    next if ($totalElements == 0);
                    my $_tmp = from_json($_->{name});

                    my $branch = Koha::Libraries->find($_->{branchcode});
                    my $branchname;

                    if ($branch) {
                        $branchname = $branch->branchname;
                    } else {
                        my $search_group = Koha::Library::Groups->find($_->{branchcode});
                        if ($search_group) {
                            $branchname = $search_group->description;
                        } else {
                            $branchname = C4::Context->preference('LibraryName');
                        }
                    }

                    push @otherlibraries, {'branchcode' => $_->{branchcode}, 'branchname' => $branchname, 'idBulletin' => $_->{idBulletin}, 'bulletinName' => $_tmp->{$lang}};
                }

                #Ordenamos el listado de bibliotecas por el nombre de la biblioteca
                @otherlibraries =  sort { $a->{branchname} cmp $b->{branchname} } @otherlibraries;

                $template->param( 'otherlibraries' => \@otherlibraries );
            }

            if (scalar(@$_bulletinContents)){
                $template->param( 'branchName' => $branchName );
                $template->param( 'bulletinID' => $bulletin->{idBulletin} );
                $template->param( 'bulletinName' => $_bulletinName->{$lang} );
                $template->param( 'bulletinDescription' => $_bulletinDescription->{$lang} );
                $template->param( 'bulletinDefaultView' => $bulletin->{'defaultView'} );
                $template->param( 'bulletin' => to_json($content) );

                my %settings = GetBulletinSettings($plugin_self);

                foreach my $key (keys %settings){
                    if ($key eq 'AuthorTruncate') {
                        my $valorAuthor = from_json($settings{$key});
                        if ($valorAuthor->{'size'}) {
                            $template->param( 'sizeau' => $valorAuthor->{'size'} );
                        } 
                        if ($valorAuthor->{'marker'}) {
                            $template->param( 'markerau' => $valorAuthor->{'marker'} );
                        }
                    } elsif ($key eq 'TitleTruncate') {
                        my $valorTitle = from_json($settings{$key});
                        if ($valorTitle->{'size'}) {
                            $template->param( 'sizeti' => $valorTitle->{'size'} );
                        } 
                        if ($valorTitle->{'marker'}) {
                            $template->param( 'markerti' => $valorTitle->{'marker'} );
                        }
                    } elsif ($key eq 'AbstractTruncate') {
                        my $valorAbstract = from_json($settings{$key});
                        if ($valorAbstract->{'size'}) {
                            $template->param( 'sizeab' => $valorAbstract->{'size'} );
                        } 
                        if ($valorAbstract->{'marker'}) {
                            $template->param( 'markerab' => $valorAbstract->{'marker'} );
                        }
                    } elsif ($key eq 'Routes') {
                        $template->param( 'route_type' => $settings{$key} );
                    }
                }

                my @formatFilters;
                my @languageFilters;
                my @yearFilters;
                foreach (@$_bulletinContents){
                    push @formatFilters, $_->{format} if ($_->{format} && (not $_->{format} ~~ @formatFilters));
                    push @languageFilters, $_->{language} if ($_->{language} && (not $_->{language} ~~ @languageFilters));
                    push @yearFilters, $_->{publicationyear} if ($_->{publicationyear} && (not $_->{publicationyear} ~~ @yearFilters));
                }

                @yearFilters = sort { $b <=> $a } @yearFilters;

                $template->param(
                    'formatfilters'   => \@formatFilters,
                    'languagefilters' => \@languageFilters,
                    'yearfilters'     => \@yearFilters
                );

            } else {
                $template->param( 'nobulletin' => 1 );
            }
        }else{
            if ($export eq "html"){
                my $exportcontent = "";
                my $iteminfo_branchcode = undef;
                $iteminfo_branchcode = $bulletin->{branchcode} if ($bulletin->{itemInfo});
                my $_bulletinName = from_json($bulletin->{'name'});
                my $_bulletinContents = GetBulletinContents($plugin_self, $bulletin->{idBulletin}, 1, 0, $iteminfo_branchcode, 1);
                my $i = 0;
                foreach (@$_bulletinContents){

                    my $coverurl = "https://images-na.ssl-images-amazon.com/images/P/".$_->{isbn}.".jpg";

                    my $av_format = Koha::Template::Plugin::AuthorisedValues->GetByCode( 'FORMAT', $_->{format} , 'opac' );
                    my $format;
                    if($av_format){
                        $format = $av_format;
                    } else {
                        $format = $_->{format};
                    }

                    $exportcontent .= '
                        <div style="width: 500px; min-height: 150px; border:1px solid #ccc; margin-bottom:20px; float:left; margin-right:15px;">
                            <div class="cover" style="float:left;"><a href="'.$catalogUrl.'/cgi-bin/koha/opac-detail.pl?biblionumber='.$_->{biblionumber}.'" target="_blank"><img src="'.$coverurl.'" style="height:170px; width:auto; padding: 10px;"/></a></div>
                            <div class="data">
                                <div style="padding-top: 10px;"><strong>'.$_->{title}.'</strong></div>
                                <div style="padding-top: 10px;">'.$_->{author}.'</div>
                                <div style="padding-top: 10px;">'.$format.'</div>
                                <div style="padding-top: 10px;">'.$_->{publicationyear}.'</div>
                            </div>';
                    if($_->{abstract}){
                        $exportcontent .= '<div>
                                '.$_->{abstract}.'
                            </div>';
                    }
                    if ($bulletin->{itemInfo}) {
                        my $items = $_->{items};
                        my $number = scalar @$items;
                        if($number > 0){
                            $exportcontent .= '<table class="data" style="width: 500px;float:left;text-align:center" >';

                            if ($lang eq 'en') {
                                $exportcontent .= Encode::decode('UTF-8','<thead><tr><th>Itemcallnumber</th><th>Location</th><th>Item type</th></tr></thead>');
                            } elsif($lang eq 'gl'){
                                $exportcontent .= Encode::decode('UTF-8','<thead><tr><th>Sinatura</th><th>Localización en estanterías</th><th>Tipo de exemplar</th></tr></thead>');
                            } elsif($lang eq 'es-ES'){
                                $exportcontent .= Encode::decode('UTF-8','<thead><tr><th>Signatura</th><th>Localización en estanterías</th><th>Tipo de ejemplar</th></tr></thead>');
                            } else {
                                $exportcontent .= Encode::decode('UTF-8','<thead><tr><th>Sinatura</th><th>Localización en estanterías</th><th>Tipo de exemplar</th></tr></thead>');
                            }

                            $exportcontent .= '<tbody>';
                            foreach my $item (@$items){
                                $item->{'location_description'} = C4::Biblio::GetAuthorisedValueDesc('','', $item->{'location'} ,'','','LOC', 1);
                                $exportcontent .= '<tr><td>'.$item->{'itemcallnumber'}.'</td><td>'.$item->{'location_description'}.'</td><td>'.$item->{'itemtype'}.'</td></tr>';
                            }
                            $exportcontent .= '</tbody>';
                            $exportcontent .= '</table>';
                        }
                    }
                    $i++;
                    $exportcontent .= '
                        </div>
                    ';
                    if ( $i % 3 == 0 ) {
                        $exportcontent .= '<div style="clear:both"></div>';
                    }

                }
                
                print $cgi->header(
                    -type       => 'text/html',
                    -charset    => 'utf-8',
                    -attachment =>  $_bulletinName->{$lang}.".html"
                );
                
                print $exportcontent;
                
                exit;
            }elsif ($export eq "rtf"){
                use Encode;
                my $exportcontent = "<table>";
                my $iteminfo_branchcode = undef;
                $iteminfo_branchcode = $bulletin->{branchcode} if ($bulletin->{itemInfo});
                my $_bulletinName = from_json($bulletin->{'name'});
                my $_bulletinContents = GetBulletinContents($plugin_self, $bulletin->{idBulletin}, 1, 0, $iteminfo_branchcode, 1);

                foreach (@$_bulletinContents){

                    my $coverurl = "https://images-na.ssl-images-amazon.com/images/P/".$_->{isbn}.".jpg";

                    my $av_format = Koha::Template::Plugin::AuthorisedValues->GetByCode( 'FORMAT', $_->{format} , 'opac' );
                    my $format;
                    if($av_format){
                        $format = $av_format;
                    } else {
                        $format = $_->{format};
                    }

                    $exportcontent .= '
                        <tr>
                            <td valign="top">
                                <img src="'.$coverurl.'" style="height:170px; width:117px;"/>
                            </td>
                            <td valign="top">
                                <p><strong>'.Encode::encode_utf8($_->{title}).'</strong></p>
                                <p>'.Encode::encode_utf8($_->{author}).'</p>
                                <p>'.Encode::encode_utf8($format).'</p>
                                <p>'.$_->{publicationyear}.'</p>
                                <p>'.Encode::encode_utf8($_->{abstract}).'</p>
                            </td>
                        </tr>';

                    if ($bulletin->{itemInfo}) {
                        my $items = $_->{items};
                        my $number = scalar @$items;
                        if($number > 0){
                            $exportcontent .= '<tr><td><table>';

                            if ($lang eq 'en') {
                                $exportcontent .= '<thead><tr><th>Itemcallnumber</th><th>Location</th><th>Item type</th></tr></thead>';
                            } elsif($lang eq 'gl'){
                                $exportcontent .= '<thead><tr><th>Sinatura</th><th>Localización en estanterías</th><th>Tipo de exemplar</th></tr></thead>';
                            } elsif($lang eq 'es-ES'){
                                $exportcontent .= '<thead><tr><th>Signatura</th><th>Localización en estanterías</th><th>Tipo de ejemplar</th></tr></thead>';
                            } else {
                                $exportcontent .= '<thead><tr><th>Sinatura</th><th>Localización en estanterías</th><th>Tipo de exemplar</th></tr></thead>';
                            }

                            $exportcontent .= '<tbody>';
                            foreach my $item (@$items){
                                $item->{'location_description'} = C4::Biblio::GetAuthorisedValueDesc('','', $item->{'location'} ,'','','LOC', 1);
                                $exportcontent .= '<tr><td>'.Encode::encode_utf8($item->{'itemcallnumber'}).'</td><td>'.Encode::encode_utf8($item->{'location_description'}).'</td><td>'.Encode::encode_utf8($item->{'itemtype'}).'</td></tr>';
                            }
                            $exportcontent .= '</tbody>';
                            $exportcontent .= '</table></td></tr>';
                        }
                    }
                }
                
                $exportcontent .= "</table>";
                
                print $cgi->header(-type => 'application/vnd.sun.xml.writer',
                    -encoding   => 'utf-8',
                    -attachment => $_bulletinName->{$lang} . ".rtf",
                    -filename   => $_bulletinName->{$lang} . ".rtf" );

                print $exportcontent;

                exit;
            }
        }
    }else{
        $template->param('nopermission' => 1);
    }

} else {
    $template->param( 'nobulletin' => 1 );    
}

sub GetQleesImage {
    my $isxn = shift;
    
    my $Qlees = new Qlees();
    $Qlees->GetXML($isxn);
    my $content = $Qlees->GetXMLData();

    my $image = "";

    my @QleesImagenes = $Qlees->GetImage($isxn);
    if (scalar(@QleesImagenes) > 0){
        $image = $QleesImagenes[0]->{content};
    }

    return $image;
}

output_html_with_http_headers $cgi, $cookie, $template->output, undef, { force_no_caching => 1 };


