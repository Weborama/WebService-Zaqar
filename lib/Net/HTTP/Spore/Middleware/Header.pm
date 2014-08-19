package Net::HTTP::Spore::Middleware::Header;

# ABSTRACT: middleware for adding a simple header to all requests

use Moose;
extends 'Net::HTTP::Spore::Middleware';

has header_name => (isa => 'Str', is => 'ro', required => 1);
has header_value => (isa => 'Str', is => 'ro', required => 1);

sub call {
    my ($self, $req) = @_;
    $req->header($self->header_name => $self->header_value);
}

1;
