package Koha::Plugin::Es::Xercode::BulletinsCreator::bulletins::BulletinsFunctions;

use strict;
use warnings;
use C4::Koha qw( GetNormalizedISBN NormalizeISSN );
use C4::Charset qw( StripNonXmlChars );
use MARC::Record;
use MARC::File::XML;
use Koha::Patrons;
use Koha::DateUtils;
use C4::Biblio qw( GetXmlBiblio GetBiblioData );
use YAML qw(Load);
use Koha::AuthorisedValues;
use utf8;
use Text::Truncate;
use Koha::Libraries;

use vars qw($VERSION @ISA @EXPORT);

BEGIN {
    $VERSION = 1;

    require Exporter;
    @ISA = qw( Exporter );

    # EXPORTED FUNCTIONS.
    push @EXPORT, qw(
        &GetNormalizedISSN
        &getBiblioMaterialType
        &GetItemsCount
        &CheckOrder
        &FixOrder
        &SetOrder
        &GetBulletinInfo
        &DeleteBulletin
        &GetBulletinContents
        &AddToBulletin
        &GetBulletinSettings
        &CompleteParams
        &GetBulletinBranches
        &GetNextPosition
        &GetBulletinContentsCount
        &GetFormatIcon
        &IsHiddenInOpac
        &GetWholeShelvesWithContent
        &GetBulletinHiddenContent
        &GetBulletinsOfType
        &GetBulletins
        &GetSettingsValue
        &GetBulletinGroups
        &UpdateFilter
        &filter
        &BulletinExists
        &HideItem
        &ShowItem
        &RemoveItem
	&Enable_Disable_Bulletin
    );
}

sub filter {
    my ($value, $config ) = @_;
    my $size = $config->{size} || 25;
    my $marker = $config->{marker} || "...";
    my $val = truncstr($value, $size, $marker);
    return $val;
}

sub RemoveItem {
    my ($self, $bulletinid, $biblionumber) = @_;
    my $table_contents = $self->get_qualified_table_name('bulletins_contents');
    my $dbh = C4::Context->dbh;
    my $sql = "DELETE FROM `$table_contents` WHERE bulletinid = ? AND biblionumber = ? ";
    my $sth = $dbh->prepare($sql);
    $sth->execute($bulletinid,$biblionumber);
    $sth->finish();
}

sub ShowItem {
    my ($self, $bulletinid, $biblionumber) = @_;
    my $table_contents = $self->get_qualified_table_name('bulletins_contents');
    my $dbh = C4::Context->dbh;
    my $sql = "UPDATE `$table_contents` SET hidden = 0 WHERE bulletinid = ? AND biblionumber = ? ";
    my $sth = $dbh->prepare($sql);
    $sth->execute($bulletinid,$biblionumber);
    $sth->finish();
}

sub HideItem {
    my ($self, $bulletinid, $biblionumber) = @_;
    my $table_contents = $self->get_qualified_table_name('bulletins_contents');
    my $dbh = C4::Context->dbh;
    my $sql = "UPDATE `$table_contents` SET hidden = 1 WHERE bulletinid = ? AND biblionumber = ? ";
    my $sth = $dbh->prepare($sql);
    $sth->execute($bulletinid,$biblionumber);
    $sth->finish();
}

sub UpdateFilter {
    my ($self, $idBulletin, $filter) = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;
    my $sql = "UPDATE `$table_bulletins` SET filter = ? WHERE idBulletin = ? ";
    my $sth = $dbh->prepare($sql);
    $sth->execute($filter,$idBulletin);
    $sth->finish();
}

sub DeleteBulletin {
    my ($self, $bulletinid) = @_;
    my $table_contents = $self->get_qualified_table_name('bulletins_contents');
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;
    my $sql1 = "DELETE FROM `$table_contents` WHERE bulletinid = ?";
    my $sql2 = "DELETE FROM `$table_bulletins` WHERE idBulletin = ?";
    my $sth = $dbh->prepare($sql1);
    $sth->execute($bulletinid);
    $sth = $dbh->prepare($sql2);
    $sth->execute($bulletinid);
    $sth->finish(); 
}

sub Enable_Disable_Bulletin {
    my ($self, $id, $status) = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;
    my $sql = "UPDATE `$table_bulletins` SET enabled = $status WHERE idBulletin = ?";
    my $sth = $dbh->prepare($sql);
    $sth->execute($id);
    $sth->finish;
}

sub AddToBulletin {
    my ($self, %params) = @_;
    my $table_contents = $self->get_qualified_table_name('bulletins_contents');
    my $dbh = C4::Context->dbh;
    my $sql = "INSERT INTO `$table_contents` (bulletinid, biblionumber, format, language, publicationyear) VALUES(?,?,?,?,?)";
    my $sth = $dbh->prepare($sql);
    $sth->execute($params{bulletinid},$params{biblionumber},$params{format},$params{language},$params{publicationyear});
    $sth->finish;
}

sub BulletinExists {
    my ($self, $type, $branchcode, $id) = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;

    my $query = "SELECT COUNT(*) FROM `$table_bulletins` WHERE type = ? AND branchcode = ?";
    if ($id){
        $query .= " AND idBulletin != ".$id;
    }
    my $sth = $dbh->prepare($query);
    $sth->execute($type,$branchcode);

    my ($total) = $sth->fetchrow;
    $sth->finish();

    return $total;
}

sub GetBulletins {
    my ($self, $branchcode, $all)  = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;

    my $sql = "SELECT * FROM `$table_bulletins` WHERE 1 = 1 ";
    $branchcode = "*" unless ($branchcode);
    $sql .= " AND branchcode IN (?)";
    unless ($all) {
        $sql .= " AND enabled = 1"
    }
    $sql .= " ORDER BY `order`";
    my $sth = $dbh->prepare($sql);
    $sth->execute($branchcode);

    return $sth->fetchall_arrayref({});
}

sub GetBulletinsOfType {
    my ($self, $type) = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;
    my @bulletins;

    my $query = "SELECT * FROM `$table_bulletins` WHERE type = ? AND enabled = 1 order by idBulletin DESC";
    my $sth = $dbh->prepare($query);
    $sth->execute($type);

    while (my $row = $sth->fetchrow_hashref){
        push @bulletins, $row;
    }
    $sth->finish();
    return \@bulletins;
}

sub GetBulletinHiddenContent {
    my ($self, $idBulletin)  = @_;
    my $table_contents = $self->get_qualified_table_name('bulletins_contents');
    my $dbh = C4::Context->dbh;

    my @biblionumbers;
    my $sql = "SELECT biblionumber FROM `$table_contents` WHERE hidden = 1 AND bulletinid = ?";
    my $sth = $dbh->prepare($sql);
    $sth->execute( $idBulletin );
    while (my $row = $sth->fetchrow_hashref){
        my $biblionumber = $row->{'biblionumber'};
        if ($biblionumber) {
            push @biblionumbers,$biblionumber;
        }
    }
    $sth->finish();
    return @biblionumbers;
}

sub GetBulletinSettings {
    my ($self) = @_;
    my $table_settings = $self->get_qualified_table_name('bulletins_settings');
    my %settings;
    my $dbh = C4::Context->dbh;

    my $sql = "SELECT * FROM `$table_settings`";
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    
    while (my $row = $sth->fetchrow_hashref){
        my $key = $row->{'key'};
        my $value = $row->{'value'};
        $settings{$key} = $value;
    }

    $sth->finish();

    return %settings;
}

sub GetBulletinBranches {
    my ($self) = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;

    my $sql = "SELECT br.* FROM `$table_bulletins` JOIN branches br USING (branchcode) GROUP BY branchcode ORDER BY branchname";
    my $sth = $dbh->prepare($sql);
    $sth->execute();

    return $sth->fetchall_arrayref({});
}

sub GetBulletinGroups {
    my ($self) = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;

    my $sql = "SELECT library_groups.* FROM `$table_bulletins` INNER JOIN library_groups ON `$table_bulletins`.branchcode = library_groups.id WHERE library_groups.parent_id IS NULL GROUP BY `$table_bulletins`.branchcode ORDER BY library_groups.title";
    my $sth = $dbh->prepare($sql);
    $sth->execute();

    return $sth->fetchall_arrayref({});
}

sub GetBulletinContentsCount {
    my ($self, $bulletinid) = @_;
    my $table_contents = $self->get_qualified_table_name('bulletins_contents');
    my $dbh = C4::Context->dbh;

    my $sql = "SELECT COUNT(*) FROM $table_contents WHERE bulletinid = ?";
    my $sth = $dbh->prepare($sql);
    $sth->execute($bulletinid);

    my ($count) = $sth->fetchrow;
    $sth->finish();

    return $count;
}

sub GetBulletinInfo {
    my ($self, $idBulletin)  = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;

    my $sql = "SELECT * FROM `$table_bulletins` WHERE idBulletin = ?";
    my $sth = $dbh->prepare($sql);
    $sth->execute($idBulletin);

    return $sth->fetchrow_hashref;
}

sub GetBulletinContents {
    my ($self, $idBulletin, $scape_json, $limit, $branchcode, $hidden)  = @_;

    my $table_contents = $self->get_qualified_table_name('bulletins_contents');
    my $dbh = C4::Context->dbh;
    my $bulletin_info = GetBulletinInfo($self,$idBulletin);
    
    my @contents;
    my @params;
    my $sql = "SELECT bc.*,b.*, bi.issn, bi.isbn, bi.place, bi.publishercode FROM `$table_contents` bc JOIN biblio b USING (biblionumber) JOIN biblioitems bi USING (biblionumber) WHERE bulletinid = ?";
    push @params, $idBulletin;

    if ($hidden) {
        $sql .= " AND hidden = 0 ";
    }

    if ($bulletin_info->{orderByField}){
        if ($bulletin_info->{orderByField} eq "title"){
            $sql .= " ORDER BY b.title " . $bulletin_info->{orderByDirection}." ,bc.publicationyear ";
        }elsif ($bulletin_info->{orderByField} eq "author"){
            $sql .= " ORDER BY b.author " . $bulletin_info->{orderByDirection}." ,b.title ";
        }elsif ($bulletin_info->{orderByField} eq "publicationyear"){
            $sql .= " ORDER BY bc.publicationyear " . $bulletin_info->{orderByDirection}." ,b.title ";
        }
    }
    
    if ($limit){
        $sql .= " LIMIT ?";
        push @params, $limit;
    }

    my $sth = $dbh->prepare($sql);
    $sth->execute( @params );
    while (my $row = $sth->fetchrow_hashref){

        my $biblionumber = $row->{'biblionumber'};
        my $hiddenInOpac = IsHiddenInOpac($biblionumber);
        if ($hiddenInOpac) {
            if ($hidden) {
                next;
            } else {
                $row->{'hiddenInOpac'} = 1;
            }
        }

        if ($scape_json){
            foreach my $key (keys %{$row}){
                $row->{$key} =~ s/"/&#39;/g if($row->{$key});
                $row->{$key} =~ s/&quot;/&#39;/g if($row->{$key});
                $row->{$key} =~ s/'/&#39;/g if($row->{$key});
                $row->{$key} =~ s/&apos;/&#39;/g if($row->{$key});
            }
        }

        if ($row->{'title'}){
            my $title = $row->{title};
            $title =~ s/^\s+|\s+$//g;
            $title =~ s/:$//;
            $title =~ s/\/$//;
            $title =~ s/^\s+|\s+$//g;
            $row->{title} = $title;
        }
        if ($row->{'author'}){
           my $author = $row->{author};
           $author =~ s/^\s+|\s+$//g;
           $author =~ s/\($//;
           $author =~ s/\.$//;
           $author =~ s/^\s+|\s+$//g;
           $row->{author} = $author;
        }
        if ($row->{'isbn'}){
            $row->{'isbn'} = GetNormalizedISBN($row->{'isbn'});
        }
        if ($row->{'issn'}){
            $row->{'issn'} = GetNormalizedISSN($self,$row->{'issn'});
        }

        $row->{'formaticon'} = GetFormatIcon($row->{'format'});

        if ($branchcode) {
            my $sqlItems = " SELECT i.itemcallnumber, i.location, it.description AS itemtype FROM items i JOIN itemtypes it ON (it.itemtype = i.itype) WHERE biblionumber = ? AND i.homebranch = ? ";
            my $sthItems = $dbh->prepare($sqlItems);
            $sthItems->execute( $biblionumber, $branchcode );
            my $items = $sthItems->fetchall_arrayref({});
            $sthItems->finish();
            $row->{'items'} = $items;
        }

        push @contents, $row;
    }
    $sth->finish();

    return \@contents;
}

sub GetItemsCount {
    my ( $biblionumber, $searchfor, $nocountopachiddenitems ) = @_;

    # search for ...
    my $_searchfor = "";
    my $_orderby = "";
    my $yaml = C4::Context->preference('OpacHiddenItems') if ($nocountopachiddenitems);
    if ($yaml){
        $_searchfor .= " AND ";
        $yaml = "$yaml\n\n"; # YAML is anal on ending \n. Surplus does not hurt
        my $hidingrules;
        eval {
            $hidingrules = YAML::Load($yaml);
        };
        foreach my $field (keys %$hidingrules) {
            foreach my $value (@{$hidingrules->{$field}}) {
                $_searchfor .= "(items.$field IS NULL OR items.$field <> '$value' )";
                $_searchfor .= " AND ";
            }
        }
        $_searchfor =~ s/\sAND\s$//;
    }

    foreach my $_s (@$searchfor){
        my ($_cod , $_val) =  %{$_s};
        if ($_cod eq "order_by"){
            $_orderby = "items.".$_val;
            next;
        }
        if ($_cod eq "homebranch") {
            $_searchfor .= " AND " . "items.".$_cod . " IN ('". $_val ."')" if ($_val ne "" && $_val ne "ALL" );
        } elsif ($_cod eq "homebranch2") {
            $_searchfor .= " AND " . "items.homebranch IN ('". $_val ."')" if ($_val ne "" && $_val ne "ALL" );
        } elsif($_cod eq "onloan"){

            if ($_val eq 'yes') {
                $_searchfor .= " AND items.onloan IS NOT NULL ";
            } elsif($_val eq 'no') {
                $_searchfor .= " AND items.onloan IS NULL ";
            }

        } else {
            $_searchfor .= " AND " . "items.".$_cod . " LIKE '%" . $_val ."%'" if ($_val ne "" && $_val ne "ALL" );
        }
    }

    my $dbh = C4::Context->dbh;
    my $query = "SELECT count(*) FROM  items WHERE biblionumber=? $_searchfor";
    my $sth = $dbh->prepare($query);
    $sth->execute($biblionumber);
    my $count = $sth->fetchrow;  
    return ($count);
}

sub IsHiddenInOpac {
    my ($biblionumber) = @_;
    my $hidden;

    #Si tiene el 942$n cubierto, está oculto en el OPAC
    my $biblio = Koha::Biblios->find( $biblionumber );
    my $record = eval { $biblio->metadata->record };

    if (C4::Context->preference('OpacSuppression')) {
        my $opacsuppressionfield = '942';
        my $opacsuppressionfieldvalue = $record->field($opacsuppressionfield);
        if ( $opacsuppressionfieldvalue &&
         $opacsuppressionfieldvalue->subfield("n") &&
         ($opacsuppressionfieldvalue->subfield("n") == 1 || $opacsuppressionfieldvalue->subfield("n") == 2) ) {
            return 1;
        }
    }

    #Si tiene todos los ejemplares ocultos en el OPAC, el registro está oculto en el OPAC
    my @searchforAll = ({ homebranch => 'ALL' });

    my $totalItemsCount = GetItemsCount($biblionumber, \@searchforAll, 'nocounthiddenitems');

    if ($totalItemsCount > 0) {
        return 0;
    } else {
        return 1;
    }
}

sub GetWholeShelvesWithContent {
    my $dbh = C4::Context->dbh;

    my $sql = 'SELECT shelfnumber, CONCAT_WS(" ",shelfname,"(",COUNT(*),")") AS shelfname FROM virtualshelves JOIN virtualshelfcontents USING (shelfnumber) GROUP BY shelfnumber ORDER BY shelfname';
    my $sth = $dbh->prepare($sql);
    $sth->execute();

    return $sth->fetchall_arrayref({});
}

sub CheckOrder {
    my ($self,$branchcode) = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;

    my $query = "SELECT * FROM `$table_bulletins` WHERE branchcode = ? ORDER BY `order` ASC";
    my $sth = $dbh->prepare($query);
    $sth->execute($branchcode);
    my $i = 0;
    while ( my $row = $sth->fetchrow_hashref ) {
        if ($row->{'order'} != $i){
            return 1;
        }
        $i++;
    }

    return 0;
}

sub FixOrder {
    my ($self,$branchcode) = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;

    my $sql = "SELECT * FROM $table_bulletins WHERE branchcode = ?";
    my $sth = $dbh->prepare($sql);
    $sth->execute($branchcode);
    my $i = 0;
    while ( my $row = $sth->fetchrow_hashref ) {
        my $sql = "UPDATE $table_bulletins SET `order` = $i WHERE idBulletin = ?";
        my $sth = $dbh->prepare($sql);
        $sth->execute( $row->{idBulletin} );
        $sth->finish;
        $i++;
    }
}

sub SetOrder {
    my ( $self, $myPosition, $to, $idBulletin, $branchcode ) = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;
    my $newPosition = 0;

    if ($to eq "up"){
       $newPosition = $myPosition - 1;
    }else{
       $newPosition = $myPosition + 1;
    }

    my $sql = "UPDATE $table_bulletins SET `order` = $newPosition WHERE idBulletin = ?";
    my $sth  = $dbh->prepare($sql);

    my $sql2 = "UPDATE $table_bulletins SET `order` = $myPosition WHERE `order` = $newPosition AND idBulletin != ? AND branchcode = ?";
    my $sth2 = $dbh->prepare($sql2);

    $sth->execute( $idBulletin );
    $sth->finish;
    $sth2->execute( $idBulletin, $branchcode );
    $sth2->finish;
}

sub getBiblioMaterialType {
    my ($self,$biblionumber,$field) = @_;
    my $table_materialtype = $self->get_qualified_table_name('bulletins_materialtype');
    my $materialtype;
    my $dbh = C4::Context->dbh;

    my $query = "SELECT * FROM `$table_materialtype` WHERE biblionumber = ? AND field = ?";
    my $sth = $dbh->prepare($query);
    $sth->execute($biblionumber,$field);

    my $row = $sth->fetchrow_hashref();
    if ($row) {
       $materialtype = $row->{'materialtype'};
    }
    return $materialtype;
}

sub GetNormalizedISSN {
    my ($self,$issn,$marcrecord,$marcflavour) = @_;
    if ($issn) {
        # Koha attempts to store multiple ISBNs in biblioitems.isbn, separated by " | "
        # anything after " | " should be removed, along with the delimiter
        ($issn) = split(/\|/, $issn );
        return _issn_cleanup($issn);
    }

    return unless $marcrecord;

    if ($marcflavour eq 'UNIMARC') {
        my @fields = $marcrecord->field('011');
        foreach my $field (@fields) {
            my $issn = $field->subfield('a');
            if ($issn) {
                return _issn_cleanup($issn);
            }
        }
    }
    else { # assume marc21 if not unimarc
        my @fields = $marcrecord->field('022');
        foreach my $field (@fields) {
            $issn = $field->subfield('a');
            if ($issn) {
                return _issn_cleanup($issn);
            }
        }
    }
}

sub CompleteParams {
    my ($self,%params) = @_;
    my $biblionumber = $params{biblionumber};
    my $content = GetBiblioData($biblionumber);

    if($content->{'publicationyear'}){
        $content->{'year'} = $content->{'publicationyear'};
    } else {
        $content->{'year'} = $content->{'copyrightdate'};
    }     

    my $marcxml = GetXmlBiblio( $content->{'biblionumber'} ); 
    $marcxml = StripNonXmlChars( $marcxml ); #Está en C4:Charset
    my $record = MARC::Record::new_from_xml( $marcxml, "utf8", C4::Context->preference('marcflavour') ); 

    my $field008 = $record->field('008');
    my ($pos35,$pos22);
    if ($field008) {
        $pos35 = substr $field008->data(), 35, 3;
        $pos22 = substr $field008->data(), 22, 1;
    }
    my $audience;
    my $language;

    if ($pos22 && $pos22 =~/[a-z]/) {
       $audience = $pos22; 
    }

    my $biblioMaterialType = getBiblioMaterialType($self, $biblionumber, '008' );

    if (!$biblioMaterialType) {

        my $leader = $record->leader;

        my $material_configuration_mapping = {
            a => {
                a => 'BKS',
                c => 'BKS',
                d => 'BKS',
                m => 'BKS',
                b => 'CR',
                i => 'CR',
                s => 'CR',
            },
            t => 'BKS',
            c => 'MU',
            d => 'MU',
            i => 'MU',
            j => 'MU',
            e => 'MP',
            f => 'MP',
            g => 'VM',
            k => 'VM',
            o => 'VM',
            r => 'VM',
            m => 'CF',
            p => 'MX',
        };
        my $leader06 = substr($leader, 6, 1);
        my $leader07 = substr($leader, 7, 1);
        #Retrieve material type using leader06
        $biblioMaterialType = $material_configuration_mapping->{$leader06};
        #If the value returned is a ref (i.e. leader06 is 'a'), then use leader07 to get the actual material type
        if ( ($biblioMaterialType) && (ref($biblioMaterialType) eq 'HASH') ){
            $biblioMaterialType = $biblioMaterialType->{$leader07};
        }
    }

    if ($biblioMaterialType) {
        my %nonaudiencie;
        $nonaudiencie{'CR'} = 'CR - Recursos continuados';
        $nonaudiencie{'MP'} = 'MP - Mapas';
        $nonaudiencie{'MX'} = 'MX - Materias mixtos';

        if ($nonaudiencie{$biblioMaterialType}) {
            $audience = undef;
        }
    }

    if ($pos35 && $pos35 =~/[a-z]/) {
       $language = $pos35; 
    }

    #Genre
    my @field690 = $record->field(690);
    my @genres;
    foreach my $field (@field690){
        my $a = $field->subfield('a');
        $a =~ s/-//g;
        $a =~ s/\.//g;
        $a = trim($a);
        push @genres, $a; 
    }
    my %hash   = map { $_ => 1 } @genres;
    @genres = keys %hash;
    my $genre = join('|', @genres);

    #Format
    my $leader = $record->leader;
    my $pos6 = substr $leader, 6, 1;
    my $pos7 = substr $leader, 7, 1;

    my %equiv;
    $equiv{'ac'} = 'am';
    $equiv{'ad'} = 'am';
    $equiv{'am'} = 'am';
    $equiv{'aa'} = 'aa';
    $equiv{'ab'} = 'ab';
    $equiv{'as'} = 'as';
    $equiv{'c'} = 'c';
    $equiv{'d'} = 'c';
    $equiv{'j'} = 'c';
    $equiv{'e'} = 'e';
    $equiv{'f'} = 'e';
    $equiv{'g'} = 'g';
    $equiv{'i'} = 'i';
    $equiv{'k'} = 'k';
    $equiv{'m'} = 'm';
    $equiv{'o'} = 'o';
    $equiv{'p'} = 'p';
    $equiv{'r'} = 'r';
    $equiv{'t'} = 't';

    my $format;
    if ($pos6 eq 'a') {
       $format = $equiv{$pos6.$pos7};
    } else {
        $format = $equiv{$pos6};
    }
    
    $params{format} = $format;
    $params{audience} = $audience;
    $params{language} = $language;
    $params{genre} = $genre;
    my $publicationyear = $content->{'year'};
    $publicationyear =~ /^[0-9]+$/ if($publicationyear);
    $params{'publicationyear'} = $publicationyear;

    return %params;
}

sub GetSettingsValue {
    my ($valor, @array) = @_;
    my $size;
    my $marker;

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

    push @array, { size => $size, marker => $marker };  
         
    return @array;
}


sub GetNextPosition {
    my ($self, $branchcode) = @_;
    my $table_bulletins = $self->get_qualified_table_name('bulletins');
    my $dbh = C4::Context->dbh;

    my $max = 0;

    my $sql = "SELECT MAX(`order`) AS max FROM $table_bulletins WHERE branchcode = ?";
    my $sth = $dbh->prepare($sql);
    $sth->execute($branchcode);

    $max = $sth->fetchrow;
    $sth->finish();

    return $max + 1;
}

sub GetFormatIcon {
    my $format = shift;

    my $icon = "fa-exclamation-triangle";

    unless ($format) {
        return $icon;
    }

    if ($format eq 'am'){
        $icon = "fa-book";
    }elsif ($format eq 'aa'){
        $icon = "fa-file-text";
    }elsif ($format eq 'ab'){
        $icon = "fa-file-text";
    }elsif ($format eq 'as'){
        $icon = "fa-newspaper-o";
    }elsif ($format eq 'c'){
        $icon = "fa-music";
    }elsif ($format eq 'e'){
        $icon = "fa-map";
    }elsif ($format eq 'g'){
        $icon = "fa-video-camera";
    }elsif ($format eq 'i'){
        $icon = "fa-volume-up";
    }elsif ($format eq 'k'){
        $icon = "fa-picture-o";
    }elsif ($format eq 'm'){
        $icon = "fa-floppy-o";
    }elsif ($format eq 'o'){
        $icon = "fa-cube";
    }elsif ($format eq 'p'){
        $icon = "fa-cube";
    }elsif ($format eq 'r'){
        $icon = "fa-cubes";
    }elsif ($format eq 't'){
        $icon = "fa-book";
    }
    
    return $icon;
}

sub _issn_cleanup {
    my ($issn) = @_;
    if ($issn){
        $issn =~ s/\(.*\)//g;
        $issn =~ s/\[.*\]//g;
        $issn =~ s/^\s+//g;
        $issn =~ s/\s+$//g;
    }
    return NormalizeISSN({ issn => $issn, strip_hyphens => 1 }) if $issn;
}

1;
