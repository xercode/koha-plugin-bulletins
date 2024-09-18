package Koha::Plugin::Es::Xercode::BulletinsCreator::api::Controller;

use Modern::Perl;

use C4::Context;
use Koha::Plugin::Es::Xercode::BulletinsCreator;
use Koha::Plugin::Es::Xercode::BulletinsCreator::bulletins::BulletinsFunctions;
use Mojo::Base 'Mojolicious::Controller';
use JSON;

use Try::Tiny;

=head1 Koha::Plugin::Es::Xercode::BulletinsCreator::api::Controller

A class implementing the controller code for Bulletins requests

=head2 Class methods

=head3 get

Method that adds a new order from a GOBI request

=cut

my $plugin_self = Koha::Plugin::Es::Xercode::BulletinsCreator->new(); #Actua como el $self para pasarselo a las funciones

#Get bulletins with their id
sub get_bulletin_id {
    my $c = shift->openapi->valid_input or return;

    my $bulletin_id   = $c->validation->param('bulletin_id');

    return try {

        my $content = GetBulletinInfo($plugin_self, $bulletin_id);
        my @elementos;

        my $elements = GetBulletinContents($plugin_self, $bulletin_id);
        $content->{'elements'} = $elements;

        my $json = JSON->new->allow_nonref;
        my $json_text = $json->encode($content);
        return $c->render(
            status => 200,
            text   => $json_text
        );
    }
    catch {
        return $c->render(
            status  => 500,
            openapi => { error => "Unhandled exception ($_)" }
        );
    };
}

#Get all bulletins from a library
sub get_all_bulletins_branch {
    my $c = shift->openapi->valid_input or return;

    my $bulletins_branch = $c->validation->param('bulletins_branch');

    return try {
        my $content = GetBulletins($plugin_self, $bulletins_branch);
        my @elementos;

        foreach my $b (@$content){
            my $elements = GetBulletinContents($plugin_self, $b->{'idBulletin'});
            $b->{'elements'} = $elements;
        }
        
        my $json = JSON->new->allow_nonref;
        my $json_text = $json->encode($content);
        return $c->render(
            status => 200,
            text   => $json_text
        );
    }
    catch {
        return $c->render(
            status  => 500,
            openapi => { error => "Unhandled exception ($_)" }
        );
    };
}

1;