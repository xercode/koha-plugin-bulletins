package Koha::Plugin::Es::Xercode::BulletinsCreator;

use Modern::Perl;
use Koha::Plugins::Base;
use base qw(Koha::Plugins::Base);

use utf8;
use C4::Context;
use POSIX qw(floor);
use CGI qw ( -utf8 );
use C4::Output;
use JSON;
use Encode;
use C4::Languages qw(getTranslatedLanguages);
use Koha::Plugin::Es::Xercode::BulletinsCreator::bulletins::BulletinsFunctions;
use C4::Koha qw(GetAuthorisedValues);
use Text::CSV::Encoded;
use Koha::Template::Plugin::AuthorisedValues;
use C4::Biblio qw( GetXmlBiblio GetBiblioData );

use constant ANYONE => 2;

BEGIN {
    use Config;
    use C4::Context;

    my $pluginsdir  = C4::Context->config('pluginsdir');
}

our $VERSION = "1.1.0";

our $metadata = {
    name            => 'Koha Plugin Bulletins Creator',
    author          => 'Xercode Media Software S.L.',
    description     => 'Plugin que permite la creación y configuración de boletines',
    date_authored   => '2023-04-24',
    date_updated    => '2024-06-04',
    minimum_version => '18.11',
    maximum_version => undef,
    version         => $VERSION,
};

our $dbh = C4::Context->dbh();

############################################
#                   NEW                    #
############################################
sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;
    
    my $self = $class->SUPER::new($args);

    return $self;
}

############################################
#               API FUNCTIONS              #
############################################
sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('api/openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}
sub api_namespace {
    my ($self) = @_;

    return 'bulletinscreator';
}

############################################
#                 OPAC JS                  #
############################################
sub opac_js {
    my ($self) = @_;
    my $cgi = $self->{'cgi'};
	my $output = "";
    my $html = "";

    my $bulljs = $self->mbf_read('js/bulletins.js');
    my $bullcss = $self->mbf_read('css/bulletins.css');
    $output .= "\n<style>\n";
    $output .= $bullcss;
    $output .= "\n</style>";
    $output .= "\n<script>\n";
    $output .= $bulljs;
    $output .= "\n</script>";

    my $mainJs = $self->mbf_read('js/opac_carousel.js');
    my $lib_tiny = $self->mbf_read('js/lib/tiny/tiny-slider.js');
    my $lib_configuration_tiny = $self->mbf_read('js/lib/tiny/configuration-tiny.js');
    my $lib_css_tiny = $self->mbf_read('css/tiny/tiny-slider.css');
    my $lib_css_carousel_tiny = $self->mbf_read('css/tiny/carousel-tiny-slider.css');

    my $OPACLocalCoverImages = C4::Context->preference('OPACLocalCoverImages');

    my @contentbulletins;

    my $homebranch;
    if (C4::Context->userenv) {
        $homebranch = C4::Context->userenv->{'branch'};
    }

    my $library = Koha::Libraries->find($homebranch);
    my $lang = C4::Languages::getlanguage($cgi);

    my %settings = GetBulletinSettings($self);

    my ($valorAuthor, $valorTitle, @arrayA, @arrayT, $routes_type);
    foreach my $key (keys %settings){
        if ($key eq 'AuthorTruncate') {
            $valorAuthor = from_json($settings{$key});
        } elsif ($key eq 'TitleTruncate') {
            $valorTitle = from_json($settings{$key});
        } elsif ($key eq 'Routes') {
            $routes_type = $settings{$key};
        }
    }
    my @arrayAuthor = GetSettingsValue($valorAuthor, @arrayA);
    my @arrayTitle = GetSettingsValue($valorTitle, @arrayT);

    my $bulletins;
    $bulletins = GetBulletins($self, $homebranch) if($homebranch);

    my ($lastbiblios,$topissues);
    foreach my $bulletin (@$bulletins){
        if($bulletin->{'type'} eq 'LASTBIBLIOS'){
            $lastbiblios = 1;
        } elsif($bulletin->{'type'} eq 'TOPISSUES'){
            $topissues = 1;
        }
    }

    if (scalar(@$bulletins) == 0){
        $bulletins = GetBulletins($self);
    } else {
        my $netBulletins = GetBulletins($self);
        foreach my $net (@$netBulletins){
            if ($net->{'type'} eq 'LASTBIBLIOS' && $lastbiblios) {
                next;
            }
            if ($net->{'type'} eq 'TOPISSUES' && $topissues) {
                next;
            }
            push @$bulletins, $net;
        }
    }

    my @contents;

    foreach (@$bulletins){
        my $limit = $_->{'elementsInCarousel'};
        my $_bulletinContents = GetBulletinContents($self, $_->{idBulletin}, 1, $limit, undef, 1);
        my $_bulletinName = from_json($_->{'name'});
        my $_bulletinDescription = from_json($_->{'description'});

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

        push @contents, { 'id' =>, $_->{idBulletin}, 'name' =>, $_bulletinName->{$lang}, 'description' =>, $_bulletinDescription->{$lang}, 'contents' => \@$_bulletinContents, 'branchname' => $branchname, 'order' => $_->{'order'} } if (scalar(@$_bulletinContents));
    }

    my ($at,$by);
    if ($lang eq 'es-ES') {
        $at = 'en';
        $by = 'por';
    } elsif ($lang eq 'gl') {
        $at = 'en';
        $by = 'por';
    } else {
        $at = 'at';
        $by = 'by';
    }

    if (scalar(@contents)){
        @contents =  sort { $a->{order} <=> $b->{order} } @contents; #ordenamos por el tipo

        $output .= "\n<style>\n";
        $output .= $lib_css_tiny;
        $output .= "\n".$lib_css_carousel_tiny;
        $output .= "\n</style>";
        
        $output .= "\n<script>\n";
        
        $html .= "<div id=\\\"bulletins-container\\\" class=\\\"hidden\\\">";
        
        foreach my $bulletin (@contents) {
            if ($routes_type eq 'CGI') {
                $html .= "<h3 class=\\\"title\\\"><a href=\\\"/cgi-bin/koha/opac-bulletin.pl?id=".$bulletin->{'id'}."\\\">".$bulletin->{'name'}." $at ".$bulletin->{'branchname'}."</a></h3>";
            } else {
                $html .= "<h3 class=\\\"title\\\"><a href=\\\"/bulletins/opac-bulletin.pl?id=".$bulletin->{'id'}."\\\">".$bulletin->{'name'}." $at ".$bulletin->{'branchname'}."</a></h3>"; 
            }               
            $html .= "<div id=\\\"tnscarousel-".$bulletin->{'id'}."\\\" class=\\\"tnscarousel\\\">";
                
            my $items_bulletins_content = $bulletin->{'contents'};

                foreach my $content (@$items_bulletins_content){
                    my $av_format = Koha::Template::Plugin::AuthorisedValues->GetByCode( 'FORMAT', $content->{'format'} , 'opac' );
                    my $format;
                    if($av_format){
                        $format = $av_format;
                    } else {
                        $format = $content->{'format'};
                    }

                    $html .= "<div class=\\\"carousel-item\\\">"; 
                        $html .= "<div class=\\\"carousel-card\\\">";
                            $html .= "<div class=\\\"carousel-image\\\">";
                                $html .= "<a href=\\\"/cgi-bin/koha/opac-detail.pl?biblionumber=".$content->{'biblionumber'}."\\\" target=\\\"_blank\\\">";
                                $html .= "<img src=\\\"https://images-na.ssl-images-amazon.com/images/P/".$content->{'isbn'}.".jpg\\\" alt=\\\"Amazon cover image\\\" />";
                                $html .= "</a>";
                            $html .= "</div>";
                            $html .= "<div class=\\\"carousel-data\\\">";
                                $html .= "<div class=\\\"carousel-data-title\\\">";
                                $html .= "<a href=\\\"/cgi-bin/koha/opac-detail.pl?biblionumber=".$content->{'biblionumber'}."\\\" target=\\\"_blank\\\">";
                                foreach my $val (@arrayTitle) {
                                    if ($val->{'size'} && !$val->{'marker'}) {
                                        $html .= filter($content->{'title'}, {'size' => $val->{'size'}});
                                    } elsif (!$val->{'size'} && $val->{'marker'}) {
                                        $html .= filter($content->{'title'}, {'marker' => $val->{'marker'}});
                                    } else {
                                        $html .= filter($content->{'title'}, {'size' => $val->{'size'}, 'marker' => $val->{'marker'}});
                                    }
                                }
                                $html .= "</a>";
                                $html .= "</div>";
                                $html .= "<div class=\\\"carousel-data-author\\\">";
                                    if ($content->{'author'}) {
                                        foreach my $val (@arrayAuthor) {
                                            if ($val->{'size'} && !$val->{'marker'}) {
                                                $html .= "$by ".filter($content->{'author'}, {'size' => $val->{'size'}})
                                            } elsif (!$val->{'size'} && $val->{'marker'}) {
                                                $html .= "$by ".filter($content->{'author'}, {'marker' => $val->{'marker'}});
                                            } else {
                                                $html .= "$by ".filter($content->{'author'}, {'size' => $val->{'size'}, 'marker' => $val->{'marker'}});
                                            }
                                        }
                                    } else {
                                        $html .= "\&nbsp;";
                                    }
                                $html .= "</div>";
                                $html .= "<div class=\\\"carousel-data-format\\\">";
                                    $html .= "<i class=\\\"fa ".$content->{'formaticon'}."\\\"></i>";
                                    $html .= "<span>".$format."</span>";
                                $html .= "</div>";
                            $html .= "</div>";
                        $html .= "</div>";
                    $html .= "</div>";
                }
            $html .= "</div>";
        }
        $html .= "</div>";

        $mainJs .= "\nvar code = \"".$html."\"";
    
        $output .= $mainJs;
        $output .= "\n".$lib_tiny;
        $output .= "\n".$lib_configuration_tiny;
        $output .= "\n</script>";
    }   

	return $output;
}

############################################
#                  TOOL                    #
############################################
sub tool {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    my $op = $cgi->param('op') || "list";
    my $branchcode = $cgi->param('branchfilter');
    my $branchcode_group = $cgi->param('branchfilter_group');
    my $id = $cgi->param('idBulletin');
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $query;
    
    my $loggedinuser = C4::Context->userenv ? C4::Context->userenv->{number} : undef;
    my $patron;
    if ($loggedinuser){
        $patron = Koha::Patrons->find( { borrowernumber => $loggedinuser } );
    }

    unless ($branchcode) {
        if ($cgi->param('branchcode')) {
            $branchcode = $cgi->param('branchcode');
        } elsif($patron){
            $branchcode = $patron->branchcode;
        }
    }

    #Get language list
    my $lang = C4::Languages::getlanguage($cgi); 
    my @lang_list;
    my $tlangs = getTranslatedLanguages(); 
    my $numberlangs = 0;
    foreach my $language (@$tlangs) {
        next unless ($language->{language}); 
        if ($language->{language} eq "es"){
            $language->{language} = "es-ES";
        }
        push @lang_list, { language => $language }; 
        $numberlangs++;
    }

    #Default view: grid
    my $grid = floor(12 / $numberlangs);

    #Get bulletins settings 
    my %settings = GetBulletinSettings($self); 
    my $searchBulletinsPerLibrary = $settings{'SearchBulletinsPerLibrary'}; 
    my $staticBulletinsPerLibrary = $settings{'StaticBulletinsPerLibrary'}; 
    my $jsonMostIssues = $settings{'JsonMostIssues'}; 
    my $jsonLastBiblio = $settings{'JsonLastBiblio'};

    my @search_groups = Koha::Library::Groups->get_search_groups( { interface => 'staff' } )->as_list;
    @search_groups = sort { $a->title cmp $b->title } @search_groups;

    #Set template according to language
    my $template;
    my $language = C4::Languages::getlanguage();
    eval {$template = $self->get_template( { file => "templates/tool_" . $language . ".tt" } )};

    unless($template){
        $template = $self->get_template( { file => "templates/tool_en.tt" } );
    }

    #------------------------------------------#
    #--------------List bulletins--------------#
    #------------------------------------------#
    if ($op eq "list") {
        my $branches = GetBulletinBranches($self);
        my $groups = GetBulletinGroups($self);
        my $flag;

        if ($cgi->param('action')) { 
            if ($cgi->param('action') eq "fixorder") { 
                FixOrder($self,$branchcode);
            }
            if ($cgi->param('action') eq "SetOrder") { 
                SetOrder($self, $cgi->param('myPos'), $cgi->param('to'), $cgi->param('idBulletin'), $branchcode);
            }
        }

        if ($branchcode) { 
            my $selected = $branchcode;
            foreach (@$branches){
                if ($_->{branchcode} eq $selected ){
                    $_->{selected} = 1;
                    $flag = 1;
                }
            }
            foreach (@$groups){
                if ($_->{id} eq $selected ){
                    $_->{selected} = 1;
                    $flag = 1;
                }
            }
        }

        unless ($flag) {
            if ($branchcode eq '') {
                $branchcode = '';
            } else {
                $branchcode = '*' if C4::Context->IsSuperLibrarian();
            }
        }
        if ($branchcode_group eq '') {
            if ($branchcode ne '*' && $branchcode ne '' && $branchcode !~ /^[a-zA-Z ]*$/) {
                $branchcode_group = $branchcode;
            }
        }
        if ($branchcode_group ne '') {
            $branchcode = $branchcode_group;
        }

        $query = "SELECT * FROM `$table_bulletins` WHERE branchcode = '$branchcode' ORDER BY `order` ASC";
        my $sth = $dbh->prepare($query);
        $sth->execute();
        my $rows = $sth->rows;

        my @loop_data;
        my $i=0;

        while ( my $r = $sth->fetchrow_hashref ) {
            my $_names = from_json($r->{name});
            my %names = %$_names;
            my $name = "";
            foreach my $key (keys %names){
                if ($key eq $lang){
                    $name = $names{$key};
                    last;
                }
            }

            my $orderUp = "";
            my $orderDown = "";
            if ($i != 0){
                $orderUp = "/cgi-bin/koha/plugins/run.pl?action=SetOrder&amp;to=up&amp;myPos=$r->{'order'}&amp;idBulletin=$r->{'idBulletin'}&amp;branchfilter=$branchcode&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool";
            }
            if ($i < $rows - 1){
                $orderDown = "/cgi-bin/koha/plugins/run.pl?action=SetOrder&amp;to=down&amp;myPos=$r->{'order'}&amp;idBulletin=$r->{'idBulletin'}&amp;branchfilter=$branchcode&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool";
            }

            my $elements = GetBulletinContentsCount($self,$r->{idBulletin});

            my $title_group; 
            if ($branchcode_group ne '') {
                my $sth = $dbh->prepare('SELECT title FROM library_groups WHERE library_groups.parent_id IS NULL AND id = ?;');
                $sth->execute($r->{branchcode});
                $title_group = $sth->fetchrow;
            }

            push @loop_data, { idBulletin => $r->{idBulletin}, name => $name, description => $r->{description}, type => $r->{type}, value => $r->{value}, enabled => $r->{enabled}, orderUp => $orderUp, orderDown => $orderDown, branchcode => $r->{branchcode}, elements => $elements, title_group => $title_group };

            $i++;
        }

        $sth->finish;

        $template->param( op => $op ) if ($op ne "");
        $template->param( 
            branchcode => $branchcode,
            branchcode_group => $branchcode_group,
            branches => $branches,
            groups => \@$groups,
            loop => \@loop_data,
            else => 1,
            id => $id
        );

        if ($cgi->param('error')){
            $template->param(
                error => $cgi->param('error'),
                searchBulletinsPerLibrary => $searchBulletinsPerLibrary,
                staticBulletinsPerLibrary => $staticBulletinsPerLibrary,
                hiddenelements => $cgi->param('hiddenelements') 
            );
        }

        show_template($self, $template, $cgi); 
    }

    #------------------------------------------#
    #------------Add bulletin (form)-----------#
    #------------------------------------------#
    if ($op eq "add_form") {
        my $itemsPerBulletin = $settings{'ItemsPerBulletin'};
        my $itemsPerCarousel = $settings{'ItemsPerCarousel'};
        my @optionsPB = split(/,/,$itemsPerBulletin);
        my @optionsPC = split(/,/,$itemsPerCarousel);
        my $shelflist = GetWholeShelvesWithContent();

        $template->param (
            op=> $op,
            lang_list => \@lang_list,
            grid => $grid,
            jsonLastBiblio => $jsonLastBiblio,
            jsonMostIssues => $jsonMostIssues,
            branchcode => $branchcode,
            bulletinnumbers => \@optionsPB,
            carouselnumbers => \@optionsPC,
            shelflist => $shelflist,
            search_groups  => \@search_groups
        );

        if ($cgi->param('error')){
            $template->param( 
                error => $cgi->param('error'),
                searchBulletinsPerLibrary => $searchBulletinsPerLibrary,
                staticBulletinsPerLibrary => $staticBulletinsPerLibrary,
                hiddenelements => $cgi->param('hiddenelements') 
            );
        }

        show_template($self, $template, $cgi);
    }

    #------------------------------------------#
    #-----------Edit bulletin (form)-----------#
    #------------------------------------------#
    if( $op eq "edit_form" ) {
        my $itemsPerBulletin = $settings{'ItemsPerBulletin'};
        my $itemsPerCarousel = $settings{'ItemsPerCarousel'};
        my @optionsPB = split(/,/,$itemsPerBulletin);
        my @optionsPC = split(/,/,$itemsPerCarousel);
        
        my $data = GetBulletinInfo($self, $id);

        my @names;
        my $_names = from_json($data->{name});
        my %names = %$_names;
        foreach my $key (keys %names) {
            push @names, { 'language_' => $key, name => $names{$key} };
        }

        my @descriptions;
        my $_descriptions = from_json($data->{description});
        my %descriptions = %$_descriptions;
        foreach my $key (keys %descriptions) {
            push @descriptions, { 'language_' => $key, description => $descriptions{$key} };
        }
        
        $template->param(
            op => $op,
            lang_list => \@lang_list,
            grid => $grid,
            jsonLastBiblio => $jsonLastBiblio,
            jsonMostIssues => $jsonMostIssues,
            bulletinnumbers => \@optionsPB,
            carouselnumbers => \@optionsPC,
            names => \@names, 
            descriptions => \@descriptions,
            idBulletin => $data->{idBulletin},
            name => $data->{name},
            description => $data->{description},
            type => $data->{type},
            branchcode => $data->{branchcode},
            elementsInCarousel => $data->{elementsInCarousel},
            elementsInBulletin => $data->{elementsInBulletin},
            itemInfo => $data->{itemInfo},
            value => $data->{value},
            filter => $data->{filter},
            defaultView => $data->{defaultView},
            orderByField => $data->{orderByField}, 
            orderByDirection => $data->{orderByDirection},
            days => $data->{days},
            search_groups => \@search_groups
        );

        if ($cgi->param('error')){
            $template->param( 
                error => $cgi->param('error'),
                searchBulletinsPerLibrary => $searchBulletinsPerLibrary,
                staticBulletinsPerLibrary => $staticBulletinsPerLibrary,
                hiddenelements => $cgi->param('hiddenelements') 
            );
        }

        #In LIST and LASTBIBLIOS bulletins, the bulletin items will be displayed
        if ($data->{type} eq 'LIST' || $data->{type} eq 'LASTBIBLIOS') {
            my $biblios = GetBulletinContents($self, $data->{idBulletin}); 
            $template->param (biblios_list => $biblios);
        }

        #In LIST (static) bulletins, items can be added by selecting a list
        if ($data->{type} eq 'LIST'){ 
            my $shelflist = GetWholeShelvesWithContent();
            $template->param(shelflist => $shelflist);
        }

        #In LASTBIBLIOS and TOPISSUES bulletins you can't edit the name and the description
        if ($data->{type} eq 'LASTBIBLIOS' || $data->{type} eq 'TOPISSUES') {
            $template->param( readonly => 1 );
        }
        
        #Filters can be applied to LASTBIBLIOS bulletins if the bulletin has elements
        if ($data->{type} eq 'LASTBIBLIOS') {
            my $itemtypes = Koha::ItemTypes->search_with_localization;
            my $ccodes = GetAuthorisedValues("CCODE");
            my @applied_filters;
            my @filters = split (/,/,$data->{filter});

            foreach my $filter (@filters){
                my $_json = from_json($filter);
                my %json = %$_json;
                foreach my $key (keys %json){
                    my $applied_filter = {};
                    $key = trim($key);
                    my $value = trim($json{$key});
                    $applied_filter->{'key'} = $key;
                    $applied_filter->{'code'} = $value;
                    if ($key eq 'itype') {
                        my $itemtype = Koha::ItemTypes->find($value);
                        $value = $itemtype->translated_description;
                    }
                    $applied_filter->{'value'} = $value;
                    push @applied_filters,$applied_filter
                }
            }

            $template->param( 
                itemtypes => $itemtypes, 
                ccodes => $ccodes, 
                applied_filters => \@applied_filters
            );
        }

        show_template($self, $template, $cgi);
    }

    #------------------------------------------#
    #-------------Update bulletin--------------#
    #------------------------------------------#
    if( $op eq "update" ) { 
        if ($cgi->param('type') eq "TOPISSUES" && BulletinExists($self, 'TOPISSUES', $cgi->param('branchcode'), $cgi->param('idBulletin'))){
            print $cgi->redirect("run.pl?error=topissuesexists&branchfilter=$branchcode&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool"); 
        }elsif ($cgi->param('type') eq "LASTBIBLIOS" && BulletinExists($self, 'LASTBIBLIOS', $cgi->param('branchcode'), $cgi->param('idBulletin'))){
            print $cgi->redirect("run.pl?error=lastbibliosexists&branchfilter=$branchcode&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool");
        }elsif ($cgi->param('type') eq "LIST" && $staticBulletinsPerLibrary && BulletinExists($self, 'LIST', $cgi->param('branchcode'), $cgi->param('idBulletin')) >= $staticBulletinsPerLibrary ){
            print $cgi->redirect("run.pl?error=staticbulletinlimit&branchfilter=$branchcode&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool");
        }elsif ($cgi->param('type') eq "SEARCH" && $searchBulletinsPerLibrary && BulletinExists($self, 'SEARCH', $cgi->param('branchcode'), $cgi->param('idBulletin')) >= $searchBulletinsPerLibrary ){
            print $cgi->redirect("run.pl?error=searchbulletinlimit&branchfilter=$branchcode&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool");  
        }else{
            my $update = 1;

            my %names;
            my %descriptions;
            foreach my $_lang (@lang_list){
                $names{$_lang->{'language'}->{'language'}} = $cgi->param('name_'.$_lang->{'language'}->{'language'});
                $descriptions{$_lang->{'language'}->{'language'}} = $cgi->param('description_'.$_lang->{'language'}->{'language'});
            }

            my $itemInfo = $cgi->param('itemInfo');
            unless ($itemInfo) { $itemInfo = 0; }

            my $value = $cgi->param('value');
            unless ($value) { $value = undef; }

            if ($update) {
                $query = "UPDATE `$table_bulletins` SET name = ?, description = ?, type = ?, branchcode = ?, elementsInCarousel = ?, elementsInBulletin = ?, itemInfo = ?, value = ?, defaultView = ?, orderByField = ?, orderByDirection = ?, days = ? WHERE idBulletin = ?";
                
                my $days = $cgi->param('days');
                $days =~ s/-//g; #En caso de que venga un numero negativo

                my $sth = $dbh->prepare($query);
                $sth->execute(to_json(\%names), to_json(\%descriptions), $cgi->param('type'), $branchcode, $cgi->param('elementsInCarousel'), $cgi->param('elementsInBulletin'), $itemInfo, $value, $cgi->param('defaultView'), $cgi->param('orderByField'), $cgi->param('orderByDirection'), $days, $cgi->param('idBulletin'));
                $sth->finish;

                my $need_fix = CheckOrder($self,$branchcode);
                if ($need_fix) {
                    print $cgi->redirect("run.pl?branchfilter=".$branchcode."&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool&action=fixorder");
                } else {
                    print $cgi->redirect("run.pl?branchfilter=".$branchcode."&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool");
                }
            }
        }
    }

    #------------------------------------------#
    #---------------Save bulletin--------------#
    #------------------------------------------#
    if ($op eq "save") {
        if ($cgi->param('type') eq "TOPISSUES" && BulletinExists($self, 'TOPISSUES', $branchcode)) {
            print $cgi->redirect("run.pl?error=topissuesexists&branchfilter=$branchcode&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool"); 
        }elsif ($cgi->param('type') eq "LASTBIBLIOS" && BulletinExists($self, 'LASTBIBLIOS', $branchcode)) {
            print $cgi->redirect("run.pl?error=lastbibliosexists&branchfilter=$branchcode&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool");
        }elsif ($cgi->param('type') eq "LIST" && $staticBulletinsPerLibrary && BulletinExists($self, 'LIST', $branchcode) >= $staticBulletinsPerLibrary){
            print $cgi->redirect("run.pl?error=staticbulletinlimit&branchfilter=$branchcode&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool");
        }elsif ($cgi->param('type') eq "SEARCH" && $searchBulletinsPerLibrary && BulletinExists($self, 'SEARCH', $branchcode) >= $searchBulletinsPerLibrary ){
            print $cgi->redirect("run.pl?error=searchbulletinlimit&branchfilter=$branchcode&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool");
        }else{
            my %names;
            my %descriptions;
            foreach my $_lang (@lang_list){
                $names{$_lang->{'language'}->{'language'}} = $cgi->param('name_'.$_lang->{'language'}->{'language'});
                $descriptions{$_lang->{'language'}->{'language'}} = $cgi->param('description_'.$_lang->{'language'}->{'language'});
            }
            
            my $creator;
            if ($patron) {
                $creator = $patron->borrowernumber; #Logged user during the creation of the bulletin
            }
            
            my $order = GetNextPosition($self, $branchcode);
            
            my $itemInfo =  $cgi->param('itemInfo');
            unless ($itemInfo) { $itemInfo = 0; }

            my $value = $cgi->param('value'); 
            unless ($value) { $value = 0; }

            my $days = $cgi->param('days');
            $days =~ s/-//g; #En caso de que venga un numero negativo

            $query = "INSERT INTO `$table_bulletins` (`name`, `description`, `type`, `branchcode`, `elementsInCarousel`, `elementsInBulletin`, `itemInfo`, `value`, `creator`, `order`, `defaultView`, `orderByField`, `orderByDirection`, `days`) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
            my $sth = $dbh->prepare($query);
            $sth->execute(to_json(\%names), to_json(\%descriptions), $cgi->param('type'), $branchcode, $cgi->param('elementsInCarousel'), $cgi->param('elementsInBulletin'), $itemInfo, $value, $creator, $order, $cgi->param('defaultView'), $cgi->param('orderByField'), $cgi->param('orderByDirection'), $days);
            $sth->finish;

            #If the bulletin is of type LIST
            my $bulletinid = $dbh->last_insert_id(undef, undef, $table_bulletins, 'idBulletin');
            my $shelfnumber = $cgi->param('shelfnumber');
            my $cartItems = $cgi->param('cartItems');
            
            if ($shelfnumber || $cartItems) {
                my $limit = $cgi->param('elementsInBulletin');
                my @contents;

                if ($cartItems) {
                    my @biblios = split /\//, $cartItems;
                    foreach my $biblionumber (@biblios){
                        my $data = GetBiblioData($biblionumber);
                        if($data->{'publicationyear'}){
                            $data->{'year'} = $data->{'publicationyear'};
                        } else {
                            $data->{'year'} = $data->{'copyrightdate'};
                        }
                        push @contents, $data;
                    }
                }

                if ($shelfnumber) {
                    my $selfcontents;
                    my $totshelves;
                    my $shelf = Koha::Virtualshelves->find($shelfnumber);
                    my $contents = $shelf->get_contents;
                    $selfcontents = $contents->unblessed;
                    $totshelves = scalar $selfcontents;
                    foreach my $content (@$selfcontents){
                        my $biblio = Koha::Biblios->find( $content->{'biblionumber'} );
                        $content->{'title'} = $biblio->title;
                        push @contents, $content;
                    }
                }

                my $elements = scalar @contents;
                if ($elements > $limit) {
                    print $cgi->redirect("run.pl?class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool&op=edit_form&idBulletin=".$bulletinid."&error=toomanyelements");
                } else {
                    my %bulletinContent;
                    my @hidden;
                    foreach my $content (@contents){
                        my %params;
                        $params{'bulletinid'} = $bulletinid; 
                        $params{'biblionumber'} = $content->{'biblionumber'};
                        %params = CompleteParams($self,%params);
                        my $biblionumber = $content->{'biblionumber'};
                        my $hiddenInOpac = IsHiddenInOpac($biblionumber);
                        if ($hiddenInOpac) {
                            $content->{'title'} = Encode::encode('UTF-8',$content->{'title'});
                            push @hidden, $content->{'title'} if($content->{'title'});
                            next;
                        }
                        unless ($bulletinContent{$biblionumber}) {
                            AddToBulletin($self,%params);
                            $bulletinContent{$biblionumber} = $content->{'title'};
                        }
                    }

                    if (scalar @hidden > 0){
                        my $hiddenTitles = join(',',@hidden);
                        print $cgi->redirect("run.pl?class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool&op=edit_form&idBulletin=".$bulletinid."&error=hiddenelements&hiddenelements=".$hiddenTitles);
                    }
                }
            }
        }
        
        my $need_fix = CheckOrder($self,$branchcode);
        if ($need_fix) {
            print $cgi->redirect("run.pl?branchfilter=".$branchcode."&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool&action=fixorder");
        } else {
            print $cgi->redirect("run.pl?branchfilter=".$branchcode."&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool");
        }
    }

    #------------------------------------------#
    #------------Duplicate bulletin------------#
    #------------------------------------------#
    if( $op eq "duplicate_form" ) { 
        my $itemsPerBulletin = $settings{'ItemsPerBulletin'};
        my $itemsPerCarousel = $settings{'ItemsPerCarousel'};
        my @optionsPB = split(/,/,$itemsPerBulletin);
        my @optionsPC = split(/,/,$itemsPerCarousel);
        
        my $data = GetBulletinInfo($self, $id);

        my @names;
        my $_names = from_json($data->{name});
        my %names = %$_names;
        foreach my $key (keys %names) {
            push @names, { 'language_' => $key, name => $names{$key} };
        }

        my @descriptions;
        my $_descriptions = from_json($data->{description});
        my %descriptions = %$_descriptions;
        foreach my $key (keys %descriptions) {
            push @descriptions, { 'language_' => $key, description => $descriptions{$key} };
        }

        $template->param(
            op=> $op,
            lang_list => \@lang_list,
            grid => $grid,
            jsonLastBiblio => $jsonLastBiblio,
            jsonMostIssues => $jsonMostIssues,
            carouselnumbers => \@optionsPC,
            bulletinnumbers => \@optionsPB,
            names => \@names,
            descriptions => \@descriptions,
            name => $data->{name},
            description => $data->{description},
            type => $data->{type},
            branchcode => $data->{branchcode},
            elementsInCarousel => $data->{elementsInCarousel},
            elementsInBulletin => $data->{elementsInBulletin},
            itemInfo => $data->{itemInfo}, 
            value => $data->{value}, 
            filter => $data->{filter}, 
            defaultView => $data->{defaultView}, 
            orderByField => $data->{orderByField}, 
            orderByDirection => $data->{orderByDirection},
            days => $data->{days},
            search_groups  => \@search_groups
        );

        if ($cgi->param('error')) {
            $template->param( 
                error => $cgi->param('error'),
                searchBulletinsPerLibrary => $searchBulletinsPerLibrary,
                staticBulletinsPerLibrary => $staticBulletinsPerLibrary,
                hiddenelements => $cgi->param('hiddenelements') 
            );
        }

        if ($data->{type} eq 'LIST') {
            my $shelflist = GetWholeShelvesWithContent();
            $template->param(shelflist => $shelflist)
        }

        show_template($self, $template, $cgi);
    }
    
    #------------------------------------------#
    #-------------Enable bulletins-------------#
    #------------------------------------------#
    if( $op eq "enable") { 
        Enable_Disable_Bulletin($self,$id,'1');
        my $bulletinInfo = GetBulletinInfo($self, $id);
        my $branchcode = $bulletinInfo->{branchcode};
        print $cgi->redirect("run.pl?branchfilter=".$branchcode."&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool");
    }
    
    #------------------------------------------#
    #--------------Disable bulletins-----------#
    #------------------------------------------#
    if( $op eq "disable") {
        Enable_Disable_Bulletin($self,$id,'0');
        my $bulletinInfo = GetBulletinInfo($self, $id);
        my $branchcode = $bulletinInfo->{branchcode};
        print $cgi->redirect("run.pl?branchfilter=".$branchcode."&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool");
    }
    
    #------------------------------------------#
    #-------------Delete bulletins-------------#
    #------------------------------------------#
    if($op eq "delete") { 
        DeleteBulletin($self, $id);
        print $cgi->redirect("run.pl?branchfilter=".$branchcode."&class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool");
    }

    #------------------------------------------#
    #--------Hide elements on bulletins--------#
    #------------------------------------------#
    if( $op eq "hideItems" ) {
        my $bulletinid = $cgi->param('idBulletin');
        my @hidden = $cgi->multi_param('hidden');
        my $biblios = GetBulletinContents($self, $bulletinid);
        my %blackList;
        
        foreach my $hide (@hidden){
            $blackList{$hide} = $hide;
            HideItem($self, $bulletinid,$hide);
        }

        foreach my $biblio (@$biblios){
            my $biblionumber = $biblio->{'biblionumber'};
            unless ($blackList{$biblionumber}) {
                ShowItem($self,$bulletinid,$biblionumber);
            }
        }

        print $cgi->redirect("run.pl?class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool&op=edit_form&idBulletin=".$bulletinid);
    }

    #------------------------------------------#
    #--------Apply filters to bulletins--------#
    #------------------------------------------#
    if( $op eq "applyFilter" ){
        my $bulletinid = $cgi->param('idBulletin');
        my $filter = $cgi->param('itemfilters');
        my $bulletinFilter = $cgi->param('filter');
        my $value;

        if ($filter) {
            $value = $cgi->param($filter);
            my %hash = ( $filter => $value );
            my $json = create_json(\%hash);
            if ($bulletinFilter) {
                if (index($bulletinFilter,$json) == -1) {
                    $json = $bulletinFilter.','.$json;
                } else {
                    $json = $bulletinFilter;
                }
            }
            UpdateFilter($self,$bulletinid,$json);
        }

        print $cgi->redirect("run.pl?class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool&op=edit_form&idBulletin=".$bulletinid);
    }

    #------------------------------------------#
    #--------Remove filters on bulletins-------#
    #------------------------------------------#
    if($op eq "removeFilters") {
        my $bulletinid = $cgi->param('idBulletin');
        my @filtersToRemove = $cgi->multi_param('remove');
        my $bulletinInfo = GetBulletinInfo($self,$bulletinid);
        my $filters = $bulletinInfo->{filter};
        my %mask;
        my $newFilter;
        my @newFilters;

        foreach my $filterToRemove (@filtersToRemove){
            $mask{$filterToRemove} = $filterToRemove;
        }

        if ($filters) {
            my @filtersInBulletin = split /,/,$filters;
            foreach my $filterInBulletin (@filtersInBulletin){
                unless ($mask{$filterInBulletin}) {
                    push @newFilters,$filterInBulletin;
                }
            }
        }

        my $number = scalar @newFilters;
        if ($number > 0) {
            $newFilter = join(',',@newFilters);
        } else {
            $newFilter = undef;
        }

        UpdateFilter($self,$bulletinid,$newFilter);
        print $cgi->redirect("run.pl?class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool&op=edit_form&idBulletin=".$bulletinid);
    }

    #------------------------------------------#
    #---------Add items to the bulletins-------#
    #------------------------------------------#
    if($op eq "addItems") { 
        my $shelfnumber = $cgi->param('shelfnumber'); 
        my $bulletinid = $cgi->param('idBulletin');
        my $cartItems = $cgi->param('cartItems');

        my %bulletinContent;
        my $elements = 0;
        my $biblios = GetBulletinContents($self,$bulletinid);
        foreach my $biblio (@$biblios){
            my $biblionumber = $biblio->{'biblionumber'};
            my $title = $biblio->{'title'};
            $bulletinContent{$biblionumber} = $title;
            $elements++;
        }

        my @contents;
        if ($cartItems) { 
            my @biblios = split /\//, $cartItems;
            foreach my $biblionumber (@biblios){
                my $data = GetBiblioData($biblionumber);
                if($data->{'publicationyear'}){
                    $data->{'year'} = $data->{'publicationyear'};
                } else {
                    $data->{'year'} = $data->{'copyrightdate'};
                }                
                push @contents, $data;
            }
        }

        if ($shelfnumber) {
            my $selfcontents;
            my $totshelves;
            my $shelf = Koha::Virtualshelves->find($shelfnumber);
            my $contents = $shelf->get_contents;
            $selfcontents = $contents->unblessed;
            $totshelves = scalar $selfcontents;
            foreach my $content (@$selfcontents){
                my $biblio = Koha::Biblios->find($content->{'biblionumber'} );
                $content->{'title'} = $biblio->title;
                push @contents, $content;
            }
        }

        my $bulletinInfo = GetBulletinInfo($self,$bulletinid);
        my $elementsInBulletin = $bulletinInfo->{elementsInBulletin}; #Check if the limit of items per bulletin has been exceeded
        $elements += scalar @contents;

        if ($elements > $elementsInBulletin) {
            print $cgi->redirect("run.pl?class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool&op=edit_form&idBulletin=".$bulletinid."&error=toomanyelements");
        } else {
            my @hidden;
            foreach my $content (@contents){
                my %params;
                $params{'bulletinid'} = $bulletinid; 
                $params{'biblionumber'} = $content->{'biblionumber'};
                %params = CompleteParams($self,%params);
                my $biblionumber = $params{'biblionumber'};
                my $hiddenInOpac = IsHiddenInOpac($biblionumber);
                if ($hiddenInOpac) {
                    $content->{'title'} = Encode::encode('UTF-8',$content->{'title'});
                    push @hidden, $content->{'title'} if($content->{'title'});
                    next;
                }
                unless ($bulletinContent{$biblionumber}) { 
                    AddToBulletin($self,%params); #Add items to the bulletins if it is not already added
                    $bulletinContent{$biblionumber} = $content->{'title'};
                }
            }    

            if (scalar @hidden > 0){
                my $hiddenTitles = join(',',@hidden);
                print $cgi->redirect("run.pl?class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool&op=edit_form&idBulletin=".$bulletinid."&error=hiddenelements&hiddenelements=".$hiddenTitles);
            }

            print $cgi->redirect("run.pl?class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool&op=edit_form&idBulletin=".$bulletinid);
        }
    }

    #------------------------------------------#
    #--------Remove items from bulletins-------#
    #------------------------------------------#
    if( $op eq "removeItems" ){
        my $bulletinid = $cgi->param('idBulletin');
        my @delete = $cgi->multi_param('delete');
        foreach my $delete (@delete){
            RemoveItem($self,$bulletinid,$delete);
        }
        print $cgi->redirect("run.pl?class=Koha%3A%3APlugin%3A%3AEs%3A%3AXercode%3A%3ABulletinsCreator&method=tool&op=edit_form&idBulletin=".$bulletinid);
    }

    #------------------------------------------#
    #-----------Export bulletins (CSV)---------#
    #------------------------------------------#
    if($op eq 'export') {
        my $bulletinid = $cgi->param('idBulletin'); 
        my $biblios = GetBulletinContents($self,$bulletinid);
        my $bulletinInfo = GetBulletinInfo($self,$bulletinid);

        my $exportItems = 0;
        if ($bulletinInfo->{itemInfo} && $bulletinInfo->{branchcode} ne "*") {
            $exportItems = 1;
        }

        my $_names = from_json($bulletinInfo->{name});
        my %names = %$_names;
        my $name = "";
        foreach my $key (keys %names){
            if ($key eq $lang){
                $name = $names{$key};
                last;
            }
        }

        my $delimiter = "\t";
        my $type = 'application/csv';
        my $content;

        my $csv = Text::CSV::Encoded->new({ encoding_out => 'UTF-8', sep_char => $delimiter});
        $csv or die "Text::CSV::Encoded->new({binary => 1}) FAILED: " . Text::CSV::Encoded->error_diag();

        if ($lang eq 'en') {
            $content .= Encode::encode('UTF-8', "Title".$delimiter."Author".$delimiter.'260$a'.$delimiter.'260$b'.$delimiter.'260$c');
        } elsif($lang eq 'gl'){
            $content .= Encode::encode('UTF-8', "Título".$delimiter."Autor".$delimiter.'260$a'.$delimiter.'260$b'.$delimiter.'260$c');
        } elsif($lang eq 'es-ES'){
            $content .= Encode::encode('UTF-8', "Título".$delimiter."Autor".$delimiter.'260$a'.$delimiter.'260$b'.$delimiter.'260$c');
        } else {
            $content .= Encode::encode('UTF-8', "Título".$delimiter."Autor".$delimiter.'260$a'.$delimiter.'260$b'.$delimiter.'260$c');
        }

        if ($exportItems){
            if ($lang eq 'en') {
                $content .= Encode::encode('UTF-8', $delimiter."Itemcallnumber".$delimiter."Location".$delimiter."Item type".$delimiter."Url\n");
            } elsif($lang eq 'gl'){
                $content .= Encode::encode('UTF-8', $delimiter."Sinatura".$delimiter."Localización".$delimiter."Tipo de ítem".$delimiter."Url\n");
            } elsif($lang eq 'es-ES'){
                $content .= Encode::encode('UTF-8', $delimiter."Signatura".$delimiter."Localización en estanterías".$delimiter."Tipo de ejemplar".$delimiter."Url\n");
            } else {
                $content .= Encode::encode('UTF-8', $delimiter."Sinatura".$delimiter."Localización".$delimiter."Tipo de ítem".$delimiter."Url\n");
            }
        }else{
            $content .= Encode::encode('UTF-8', $delimiter."Url\n");
        }
        
        foreach my $biblio (@$biblios){
            my $title = Encode::encode('UTF-8',$biblio->{'title'});
            my $author = Encode::encode('UTF-8',$biblio->{'author'});
            unless ($author) { $author = ' '; }
            my $f260a =  Encode::encode('UTF-8',$biblio->{'place'});
            my $f260b =  Encode::encode('UTF-8',$biblio->{'publishercode'});
            my $f260c;
            if($biblio->{'publicationyear'}){
                $f260c =  Encode::encode('UTF-8',$biblio->{'publicationyear'});
            } else {
                $f260c =  Encode::encode('UTF-8',$biblio->{'copyrightdate'});
            }
            unless ($f260a) { $f260a = ' '; }
            unless ($f260b) { $f260b = ' '; }
            unless ($f260c) { $f260c = ' '; }

            if ($exportItems){
                my @searchfor = (
                    { homebranch => $bulletinInfo->{branchcode} },
                    { order_by  => "itemnumber ASC" }
                );
                my @all_items = GetItemsInfo( $biblio->{biblionumber}, undef, undef, \@searchfor);
                if (scalar @all_items){
                    my $content_biblio_info = $content;
                    foreach my $item (@all_items){
                        my $av_loc = Koha::AuthorisedValues->search({ category => 'LOC', authorised_value => $item->{location} });
                        my $location = $av_loc->count ? $av_loc->next->lib : '';
                        $location =  Encode::encode('UTF-8',$location);
                        my $itemtype = Encode::encode('UTF-8',$item->{translated_description});
                        my $itemcallnumber = Encode::encode('UTF-8', $item->{itemcallnumber});
                        $content .= $title.$delimiter.$author.$delimiter.$f260a.$delimiter.$f260b.$delimiter.$f260c.$delimiter.$itemcallnumber.$delimiter.$location.$delimiter.$itemtype.$delimiter.C4::Context->preference("OPACBaseURL")."/cgi-bin/koha/opac-detail.pl?biblionumber=".$biblio->{biblionumber}."\n";
                    }
                }else{
                    $content .= $title.$delimiter.$author.$delimiter.$f260a.$delimiter.$f260b.$delimiter.$f260c.$delimiter.$delimiter.$delimiter.$delimiter.C4::Context->preference("OPACBaseURL")."/cgi-bin/koha/opac-detail.pl?biblionumber=".$biblio->{biblionumber}."\n";
                }
            }else{
                $content .= $title.$delimiter.$author.$delimiter.$f260a.$delimiter.$f260b.$delimiter.$f260c.$delimiter.C4::Context->preference("OPACBaseURL")."/cgi-bin/koha/opac-detail.pl?biblionumber=".$biblio->{biblionumber}."\n";
            }
        }

        print $cgi->header(-type => $type, -attachment=> $name.".csv");
        print $content;
        exit;
    }
}

############################################
#                CONFIGURE                 #
############################################
sub configure { 
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    my $key = $cgi->param('key');
    my $op  = $cgi->param('op') || 'list';

    #Set template according to language
    my $template;
    my $language = C4::Languages::getlanguage();
    eval {$template = $self->get_template( { file => "templates/configure_" . $language . ".tt" } )};

    unless($template){
        $template = $self->get_template( { file => "templates/configure_en.tt" } );
    }


    #Inject Library Code Mirror
    my $output = "";
    my $codemirrorJs = $self->mbf_read('js/lib/codemirror/codemirror-compressed.js');
    $output .= "\n<script>\n";
    $output .= $codemirrorJs;
    $output .= "\n</script>";
    $template->param( codemirror => $output );
    
    #------------------------------------------#
    #---------------List settings--------------#
    #------------------------------------------#
    if ($op eq "list"){
        my @settings = getSettings($cgi, $self); 
        
        my (@author, @title, @abstract);

        foreach my $setting (@settings) {
            @author = getValuesTruncate($setting, 'AuthorTruncate', @author);
            @title = getValuesTruncate($setting, 'TitleTruncate', @title);
            @abstract = getValuesTruncate($setting, 'AbstractTruncate', @abstract);
        }

        $template->param( settings => \@settings );
        $template->param( author => \@author );
        $template->param( title => \@title );
        $template->param( abstract => \@abstract );
        show_template($self, $template, $cgi);  
    }

    #------------------------------------------#
    #-------------Update settings--------------#
    #------------------------------------------#
    if ($op eq "update"){
        my $keys = getKeys($self);
        
        foreach my $key (@$keys){
            my $setting = $key->{'key'};
            my $value = $cgi->param($setting);
            
            my $author_s = $cgi->param('AuthorSize');
            my $author_m = $cgi->param('AuthorMarker');
            my $title_s = $cgi->param('TitleSize');
            my $title_m = $cgi->param('TitleMarker');
            my $abstract_s = $cgi->param('AbstractSize');
            my $abstract_m = $cgi->param('AbstractMarker');

            if ($setting eq 'AuthorTruncate') {
                if ($author_s && !$author_m) {
                    updateSettings($setting,'{"size":"'.$author_s.'","marker":""}',$self);
                } elsif (!$author_s && $author_m) {
                    updateSettings($setting,'{"size":"","marker":"'.$author_m.'"}',$self);
                } else {
                    updateSettings($setting,'{"size":"'.$author_s.'","marker":"'.$author_m.'"}',$self);
                }
            } elsif ($setting eq 'TitleTruncate') {
                if ($title_s && !$title_m) {
                    updateSettings($setting,'{"size":"'.$title_s.'","marker":""}',$self);
                } elsif (!$title_s && $title_m) {
                    updateSettings($setting,'{"size":"","marker":"'.$title_m.'"}',$self);
                } else {
                    updateSettings($setting,'{"size":"'.$title_s.'","marker":"'.$title_m.'"}',$self);
                }
            } elsif ($setting eq 'AbstractTruncate') {
                if ($abstract_s && !$abstract_m) {
                    updateSettings($setting,'{"size":"'.$abstract_s.'","marker":""}',$self);
                } elsif (!$abstract_s && $abstract_m) {
                    updateSettings($setting,'{"size":"","marker":"'.$abstract_m.'"}',$self);
                } else {
                    updateSettings($setting,'{"size":"'.$abstract_s.'","marker":"'.$abstract_m.'"}',$self);
                }
            } else {
                updateSettings($setting,$value,$self);
            }
        }

        my @settings = getSettings($cgi, $self);

        my (@author, @title, @abstract);

        foreach my $setting (@settings) {
            @author = getValuesTruncate($setting, 'AuthorTruncate', @author);
            @title = getValuesTruncate($setting, 'TitleTruncate', @title);
            @abstract = getValuesTruncate($setting, 'AbstractTruncate', @abstract);
        }

        $template->param( settings => \@settings );
        $template->param( author => \@author );
        $template->param( title => \@title );
        $template->param( abstract => \@abstract );
        $template->param( op => $op );
        show_template($self, $template, $cgi); 
    }
}

############################################
#                  INSTALL                 #
############################################
sub install() {
    my ( $self, $args ) = @_;
    my $dbh = C4::Context->dbh;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $table_contents = $self->get_qualified_table_name('bulletins_contents');
    my $table_settings = $self->get_qualified_table_name('bulletins_settings');
    my $table_materialtype = $self->get_qualified_table_name('bulletins_materialtype');

    $dbh->do("
        CREATE TABLE IF NOT EXISTS `$table_bulletins` (
          `idBulletin` int(11) unsigned NOT NULL AUTO_INCREMENT,
          `name` text,
          `description` text,
          `creator` int(11) default NULL,
          `branchcode` varchar(10) default NULL,
          `elementsInCarousel` int(11) NOT NULL,
          `elementsInBulletin` int(11) NOT NULL,
          `itemInfo` tinyint(1),
          `type` varchar(25) DEFAULT NULL,
          `value` text,
          `filter` text DEFAULT NULL,
          `enabled` tinyint(1) DEFAULT '1',
          `order` int NOT NULL,
          `defaultView` varchar(25) DEFAULT NULL,
          `updatedOn` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
          `orderByField` varchar(25) default NULL,
          `orderByDirection` varchar(25) default 'ASC',
          `days` INT(11) default NULL,
          PRIMARY KEY (`idBulletin`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ");

    $dbh->do("
        CREATE TABLE IF NOT EXISTS `$table_materialtype` (
          `biblionumber` int(11) NOT NULL,
          `field` varchar(10),
          `materialtype` varchar(10),
          KEY `biblionumber_idx` (`biblionumber`) USING BTREE,
          KEY `field_idx` (`field`) USING BTREE,
          KEY `materialtype_idx` (`materialtype`) USING BTREE,
          CONSTRAINT `bulletins_materialtype_fk1` FOREIGN KEY (`biblionumber`) REFERENCES `biblio` (`biblionumber`) ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ");

    $dbh->do("
        CREATE TABLE IF NOT EXISTS `$table_contents` (
            `bulletinid` int(11) NOT NULL,
            `biblionumber` int(11) NOT NULL,
            `dateadded` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `format` varchar(255) DEFAULT NULL,
            `language` varchar(25) DEFAULT NULL,
            `publicationyear` mediumtext DEFAULT NULL,
            `hidden`  tinyint(1) DEFAULT '0'
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ");

    $dbh->do("
        CREATE TABLE IF NOT EXISTS `$table_settings` (
            `key` varchar(50) NOT NULL,
            `value` text NOT NULL,
            `description` text,
            `name` text,
            `type` varchar(25),
            `order` int(11) DEFAULT NULL,
            PRIMARY KEY (`key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ");

    $dbh->do("INSERT IGNORE INTO `authorised_value_categories` (`category_name`) VALUES ('FORMAT');");

    my $sqlnewitems_value = q{
        SELECT b.biblionumber, MAX(dateaccessioned) AS max_dateaccessioned
            FROM items i
            JOIN biblioitems b USING (biblionumber)
            JOIN biblio_metadata bm USING (biblionumber)
            WHERE (i.withdrawn = 0 OR i.withdrawn is null OR i.withdrawn = "") 
                AND (i.itemlost = 0 OR i.itemlost is null OR i.itemlost = "")
              AND ( YEAR(i.dateaccessioned) BETWEEN YEAR(DATE_SUB(CURDATE(),INTERVAL 1 YEAR)) AND YEAR(CURDATE()) )
              AND EXTRACTVALUE( bm.metadata, \'//datafield[\@tag="942"]/subfield[\@code="n"]\' ) = 0
            GROUP BY b.biblionumber
            ORDER BY max_dateaccessioned DESC
    };

    my $sqlnewbiblios_value = q{
        SELECT bib.biblionumber
            FROM items as i
            LEFT JOIN biblioitems as bib on i.biblionumber=bib.biblionumber
            LEFT JOIN biblio_metadata as met on i.biblionumber=met.biblionumber
            LEFT JOIN biblio as b on bib.biblionumber=b.biblionumber
            WHERE (i.withdrawn = 0 OR i.withdrawn is null OR i.withdrawn = "") 
                AND (i.itemlost = 0 OR i.itemlost is null OR i.itemlost = "")
        AND bib.publicationyear >= YEAR(DATE_SUB(CURDATE(),INTERVAL 1 YEAR)) AND bib.publicationyear <= YEAR(CURDATE())
        AND EXTRACTVALUE( met.metadata, \'//datafield[\@tag="942"]/subfield[\@code="n"]\' ) = 0 
        GROUP BY bib.biblionumber
        ORDER BY bib.publicationyear DESC, datecreated DESC        
    };

    my $sqlmostissues_value = q{
        SELECT b.biblionumber,
        COUNT(*) AS tot
        FROM items i
        JOIN biblio b USING (biblionumber)
        JOIN biblioitems bi USING (biblionumber)
        JOIN biblio_metadata bm USING (biblionumber)
        JOIN (SELECT * FROM statistics WHERE type IN ("issue")) s USING (itemnumber)
        JOIN borrowers bo USING(borrowernumber)
        WHERE EXTRACTVALUE( bm.metadata, \'//datafield[\@tag="942"]/subfield[\@code="n"]\' ) = 0
        AND TO_DAYS(NOW()) - TO_DAYS(CAST(s.datetime AS DATE)) <= 365 
        GROUP BY biblionumber
        ORDER BY tot DESC
    };

    $dbh->do(
        qq{
            INSERT IGNORE INTO `$table_settings` (`key`, `value`, `type`, `description`, `name`, `order`) VALUES
            ('ItemsPerBulletin', '10,20,30,40,50', 'input', 'Número de ejemplares por boletín', '{"en":"Items per bulletin","gl":"Número de elementos por boletín","es-ES":"Número de elementos por boletín"}', '1'),
            ('ItemsPerCarousel', '5,10,15,20,25,30', 'input', 'Número de ejemplares por carrusel', '{"es-ES":"Número de elementos por carrusel","gl":"Número de elementos por carrusel","en":"Items per carousel"}', '2'),
            ('SearchBulletinsPerLibrary', 5, 'input', 'Número de boletines de tipo búsqueda que puede crear una biblioteca', '{"en":"How many bulletins of type search a library can create","es-ES":"Cuántos boletines de tipo búsqueda puede crear una biblioteca","gl":"Cantos boletíns de tipo busca pode crear unha biblioteca"}', '3'),
            ('StaticBulletinsPerLibrary', 5, 'input', 'Número de boletines de tipo estático que puede crear una biblioteca', '{"gl":"Cantos boletíns de tipo estático pode crear unha biblioteca","es-ES":"Cuántos boletines de tipo estático puede crear una biblioteca","en":"How many bulletins of type static a library can create"}', '4'),
            ('JsonLastBiblio', '{"title":{"en":"New items","es":"Novedades","gl":"Novidades"}, "description":{"en":"New items","es":"Boletín de novedades","gl":"Boletín de novidades"}}', 'textarea', 'Títulos y descripciones para los boletines de novedades', '{"es-ES":"Títulos y descripciones para los boletines de novedades","en":"Title and description for novelties bulletins","gl":"Títulos e descripcións para os boletins de novidades"}', '5'),
            ('JsonMostIssues', '{"title":{"en":"Most issued","es":"Más prestados","gl":"Máis prestados"}, "description":{"en":"The most issued records","es":"Los registros más prestados","gl":"Os rexistros máis prestados"}}', 'textarea', 'Títulos y descripciones para los boletines de más prestados', '{"es-ES":"Títulos y descripciones para los boletines de más prestados","en":"Title and description for most issued bulletins","gl":"Títulos e descripcións para os boletins de máis prestados"}', '6'),
            ('SqlMostIssues', '$sqlmostissues_value', 'textarea', 'Consulta BBDD para los registros más prestados', '{"en":"SQL - Most issued","es-ES":"SQL - Más prestados","gl":"SQL - Máis prestados"}', '7'),
            ('SqlNewBiblios', '$sqlnewbiblios_value', 'textarea', 'Consulta BBDD para las nuevas adquisiciones basada en los bibliograficos', '{"en":"SQL - Biblio level - Novelties","gl":"SQL - Nivel bibliográfico - Novidades","es-ES":"SQL - Nivel bibliográfico - Novedades"}', '8'),
            ('SqlNewItems', '$sqlnewitems_value', 'textarea', 'Consulta BBDD para las nuevas adquisiciones basada en los items', '{"gl":"SQL - Nivel item - Novidades","en":"SQL - Item level - Novelties","es-ES":"SQL - Nivel item - Novedades"}', '9'),
            ('AuthorTruncate', '{"size":"20","marker":"..."}', 'input', 'Tamaño y marcador para truncar el texto del autor', '{"gl":"Autor","es-ES":"Autor","en":"Author"}', '10'),
            ('TitleTruncate', '{"size":"25","marker":"..."}', 'input', 'Tamaño y marcador para truncar el texto del titulo', '{"gl":"Título","es-ES":"Título","en":"Title"}', '11'),
            ('AbstractTruncate', '{"size":"300","marker":"..."}', 'input', 'Tamaño y marcador para truncar el texto de información del item', '{"gl":"Item info","es-ES":"Item info","en":"Item info"}', '12'),
            ('Routes', 'CGI', 'input', 'Tipo de rutas que se establecerán. Posibilidades: Rutas PLACK o Rutas CGI', '{"gl":"Rutas con","es-ES":"Rutas con","en":"Routes with"}', '13');
        }
    );

    $dbh->do("
        INSERT IGNORE INTO `authorised_values` (`category`, `authorised_value`, `lib`, `lib_opac`, `imageurl`) VALUES
        ('FORMAT', 'am', 'Book', 'Book', ''),
        ('FORMAT', 'aa', 'Article', 'Article', ''),
        ('FORMAT', 'ab', 'Chapter', 'Chapter', ''),
        ('FORMAT', 'as', 'Serial', 'Serial', ''),
        ('FORMAT', 'c', 'Music', 'Music', ''),
        ('FORMAT', 'e', 'Map', 'Map', ''),
        ('FORMAT', 'g', 'Audiovisual', 'Audiovisual', ''),
        ('FORMAT', 'i', 'No music sound', 'No music sound', ''),
        ('FORMAT', 'k', 'Photo', 'Photo', ''),
        ('FORMAT', 'm', 'Computer files', 'Computer files', ''),
        ('FORMAT', 'o', 'Kit', 'Kit', ''),
        ('FORMAT', 'p', 'Mixed material', 'Mixed material', ''),
        ('FORMAT', 'r', 'Tridimensional objects', 'Tridimensional objects', ''),
        ('FORMAT', 't', 'Handwritten', 'Handwritten', '');
    ");

    $dbh->do("INSERT IGNORE INTO plugin_methods (plugin_class, plugin_method) VALUES ('Koha::Plugin::Es::Xercode::BulletinsCreator','api_routes')");
    $dbh->do("INSERT IGNORE INTO plugin_methods (plugin_class, plugin_method) VALUES ('Koha::Plugin::Es::Xercode::BulletinsCreator','api_namespace')");

    return 1;
}

############################################
#                  UPGRADE                 #
############################################

sub upgrade() {
    my ( $self, $args ) = @_;

    my $database_version = $self->retrieve_data('__INSTALLED_VERSION__') || 0;

    my $dbh = C4::Context->dbh;

    if ($self->_version_compare('1.0.4', $database_version) == 1) {
        my $table_settings = $self->get_qualified_table_name('bulletins_settings');
        my $table_bulletins = $self->get_qualified_table_name('bulletins');
        $dbh->do(
            qq{
                INSERT IGNORE INTO `$table_settings` (`key`, `value`, `type`, `description`, `name`, `order`) VALUES
                ('Routes', 'CGI', 'input', 'Tipo de rutas que se establecerán. Posibilidades: Rutas PLACK o Rutas CGI', '{"gl":"Rutas con","es-ES":"Rutas con","en":"Routes with"}', '13')
            }
        );
        $dbh->do(
            qq{
                ALTER TABLE `$table_bulletins` ADD `days` INT(11) default NULL
            }
        );
    }

    return 1;

}

############################################
#                 UNINSTALL                #
############################################
sub uninstall() {
    my ( $self, $args ) = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $table_contents = $self->get_qualified_table_name('bulletins_contents');
    my $table_settings = $self->get_qualified_table_name('bulletins_settings');
    my $table_materialtype = $self->get_qualified_table_name('bulletins_materialtype');

    C4::Context->dbh->do("DROP TABLE IF EXISTS $table_bulletins");
    C4::Context->dbh->do("DROP TABLE IF EXISTS $table_contents");
    C4::Context->dbh->do("DROP TABLE IF EXISTS $table_settings");
    C4::Context->dbh->do("DROP TABLE IF EXISTS $table_materialtype");
    C4::Context->dbh->do("DELETE FROM authorised_values WHERE category = 'FORMAT'");
    C4::Context->dbh->do("DELETE FROM authorised_value_categories WHERE category_name = 'FORMAT'");

    return 1;
}

############################################
#              PLUGIN METHODS              #
############################################
sub show_template {
    my ($self, $template, $cgi) = @_;
    if ( $self->retrieve_data('enabled') ) {
        $template->param(enabled => 1);
    }
    print $cgi->header({-type => 'text/html', -charset  => 'UTF-8', -encoding => "UTF-8"});
    print $template->output();
}

sub trim {
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

#-----------------------------------------------
#-------Configuration settings functions--------
#-----------------------------------------------
sub getSettings {
    my ($cgi, $self) = @_;
    my $dbh = C4::Context->dbh;
    my $table_settings = $self->get_qualified_table_name('bulletins_settings');

    my $sql = "SELECT * FROM $table_settings WHERE `key` NOT LIKE 'json%' ORDER BY `order` ASC"; 
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    my $bulletin_configuration = $sth->fetchall_arrayref({});
    $sth->finish();

    my $lang = C4::Languages::getlanguage($cgi);
    my @settings;
    foreach (@$bulletin_configuration){
        my $_tmp = from_json($_->{'name'});
        $_->{name} = $_tmp->{$lang};
        push @settings, $_;
    }

    return @settings;
}

sub updateSettings {
    my ($key, $value, $self) = @_;
    my $dbh = C4::Context->dbh;
    my $table_settings = $self->get_qualified_table_name('bulletins_settings');

    my $sql = "UPDATE $table_settings SET `value` = ? WHERE `key` = ? ";
    my $sth = $dbh->prepare($sql);
    $sth->execute($value, $key);
    $sth->finish();
}

sub getValuesTruncate {
    my ($setting, $key, @value) = @_;
    my $size = "";
    my $marker = "";

    if ($setting->{'key'} eq $key) {
        my $valor = from_json($setting->{'value'});
        
        if ($valor->{'size'}) {
            $size = $valor->{'size'};
        } else {
            $size = "''";
        }

        if ($valor->{'marker'}) {
            $marker = $valor->{'marker'};
        } else {
            $marker = "''";
        }

        push @value, { marker => $marker, size => $size };
    } 

    return @value;
}

sub getKeys {
    my ($self) = @_;
    my $table_settings = $self->get_qualified_table_name('bulletins_settings');
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("SELECT `key` FROM `$table_settings` WHERE `key` NOT LIKE 'json%'");
    $sth->execute();
    return $sth->fetchall_arrayref({});
}

1;

__END__

=head1 NAME

BulletinsCreator.pm - Koha Plugin Bulletins Creator

=head1 SYNOPSIS

Koha Plugin Bulletins Creator

=head1 DESCRIPTION

Plugin que permite la creación y configuración de boletines

=head1 AUTHOR

Nuria Villaronga

=head1 COPYRIGHT

Copyright 2023 Xercode Media Software S.L.

=head1 LICENSE

This file is part of Koha.

Koha is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later version.

You should have received a copy of the GNU General Public License along with Koha; if not, write to the Free Software Foundation, Inc., 51 Franklin Street,
Fifth Floor, Boston, MA 02110-1301 USA.

=head1 DISCLAIMER OF WARRANTY

Koha is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

=cut
