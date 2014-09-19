package Net::HTTP::Spore::Middleware::Format::JSONSometimes;
$Net::HTTP::Spore::Middleware::Format::JSON::VERSION = '0.07';
# ABSTRACT: middleware for JSON format

use JSON;
use Moose;
extends 'Net::HTTP::Spore::Middleware::Format';

has _json_parser => (
    is      => 'rw',
    isa     => 'JSON',
    lazy    => 1,
    default => sub { JSON->new->utf8(1)->allow_nonref },
);

sub encode       { $_[0]->_json_parser->encode( $_[1] ); }
sub decode       { $_[0]->_json_parser->decode( $_[1] ); }
sub accept_type  { ( 'Accept' => 'application/json' ) }
sub content_type { ( 'Content-Type' => 'application/json;' ) }

sub should_serialize {
    my $self = shift;
    $self->_check_serializer( shift->env, $self->serializer_key );
}

sub should_deserialize {
    my ($self, $response) = @_;
    $self->_check_is_authenticated( $response )
        and $self->_check_serializer( $response->env, $self->deserializer_key );
}

sub _check_is_authenticated {
    my ($self, $response) = @_;
    $response->status < 400;
}

sub _check_serializer {
    my ( $self, $env, $key ) = @_;
    if ( exists $env->{$key} && $env->{$key} == 1 ) {
        return 0;
    }
    else {
        return 1;
    }
}

sub call {
    my ( $self, $req ) = @_;

    return unless $self->should_serialize( $req );

    $req->header( $self->accept_type );

    if ( $req->env->{'spore.payload'} ) {
        $req->env->{'spore.payload'} =
          $self->encode( $req->env->{'spore.payload'} );
        $req->header( $self->content_type );
    }

    $req->env->{ $self->serializer_key } = 1;

    return $self->response_cb(
        sub {
            my $res = shift;
            if ( $res->body ) {
                return if $res->code >= 500;
                return unless $self->should_deserialize( $res );
                my $content = $self->decode( $res->body );
                $res->body($content);
                $res->env->{ $self->deserializer_key } = 1;
            }
        }
    );
}

1;


__END__
=pod

=head1 NAME

Net::HTTP::Spore::Middleware::Format::JSON - middleware for JSON format

=head1 VERSION

version 0.07

=head1 SYNOPSIS

    my $client = Net::HTTP::Spore->new_from_spec('twitter.json');
    $client->enable('Format::JSON');

=head1 DESCRIPTION

Net::HTTP::Spore::Middleware::Format::JSON is a simple middleware to handle the JSON format. It will set the appropriate B<Accept> header in your request. If the request method is PUT or POST, the B<Content-Type> header will also be set to JSON.

This middleware will also deserialize content in the response. The deserialized content will be store in the B<body> of the response.

=head1 EXAMPLES

=head1 AUTHORS

=over 4

=item *

franck cuny <franck@lumberjaph.net>

=item *

Ash Berlin <ash@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by linkfluence.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

