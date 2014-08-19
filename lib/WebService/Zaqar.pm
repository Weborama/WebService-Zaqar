package WebService::Zaqar;

use strict;
use warnings;
use 5.010;
use Carp;
use autodie;
use utf8;

use Moo;
use HTTP::Request;
use JSON;
use Net::HTTP::Spore;
use List::Util qw/first/;
use Data::UUID;

has 'base_url' => (is => 'ro',
                   writer => '_set_base_url');
has 'token' => (is => 'ro',
                writer => '_set_token',
                clearer => '_clear_token',
                predicate => 'has_token');
has 'spore_client' => (is => 'ro',
                       lazy => 1,
                       builder => '_build_spore_client');
has 'spore_description_file' => (is => 'ro',
                                 required => 1);
has 'client_uuid' => (is => 'ro',
                      lazy => 1,
                      builder => '_build_uuid');

sub _build_uuid {
    return Data::UUID->new->create_str;
}

sub _build_spore_client {
    my $self = shift;
    my $client = Net::HTTP::Spore->new_from_spec($self->spore_description_file,
                                                 base_url => $self->base_url);
    # all payloads serialized/deserialized to/from JSON
    $client->enable('Format::JSON');
    # set X-Auth-Token header to the Cloud Identity token, if
    # available (local instances don't use that, for instance)
    $client->enable('Auth::DynamicHeader',
                    header_name => 'X-Auth-Token',
                    header_value_callback => sub {
                        # HTTP::Headers says, if the value of the
                        # header is undef, the field is removed
                        return $self->has_token ? $self->token : undef
                    });
    # all requests should contain a Date header with an RFC 1123 date
    $client->enable('DateHeader');
    # each client using the queue should provide an UUID; the docs
    # recommend that for a given client it should persist between
    # restarts
    $client->enable('Header',
                    header_name => 'Client-ID',
                    header_value => $self->client_uuid);
    return $client;
}

sub rackspace_authenticate {
    my ($self, $cloud_identity_uri, $username, $apikey) = @_;
    my $request = HTTP::Request->new('POST', $cloud_identity_uri,
                                     [ 'Content-Type' => 'application/json' ],
                                     JSON::encode_json({
                                         auth => {
                                             'RAX-KSKEY:apiKeyCredentials' => {
                                                 username => $username,
                                                 apiKey => $apikey } } }));
    my $response = $self->spore_client->api_useragent->request($request);
    my $content = $response->decoded_content;
    my $structure = JSON::decode_json($content);
    my $token = $structure->{access}->{token}->{id};
    $self->_set_token($token);
    # the doc says we should read the catalog to determine the
    # endpoint...
    # my $catalog = first { $_->{name} eq 'cloudQueues'
    #                           and $_->{type} eq 'rax:queues' } @{$structure->{serviceCatalog}};
    return $token;
}

our $AUTOLOAD;
sub AUTOLOAD {
    my $method_name = $AUTOLOAD;
    my ($self, @rest) = @_;
    my $current_class = ref $self;
    $method_name =~ s/^${current_class}:://;
    $self->spore_client->$method_name(@rest);
}

1;
__END__
=pod

=head1 NAME

WebService::Zaqar -- Wrapper around the Zaqar (aka Marconi) message queue API

=head1 SYNOPSIS

  use WebService::Zaqar;
  my $client = WebService::Zaqar->new(
      # base_url => 'https://dfw.queues.api.rackspacecloud.com/',
      base_url => 'http://localhost:8888',
      spore_description_file => 'share/marconi.spore.json');
  
  # for Rackspace only
  my $token = $client->rackspace_authenticate('https://identity.api.rackspacecloud.com/v2.0/tokens',
                                              $rackspace_account,
                                              $rackspace_key);
  
  $client->create_queue(queue_name => 'pets');
  $client->post_messages(queue_name => 'pets',
                         payload => [
                             { ttl => 120,
                               body => [ 'pony', 'horse', 'warhorse' ] },
                             { ttl => 120,
                               body => [ 'little dog', 'dog', 'large dog' ] } ]);
  $client->post_messages(queue_name => 'pets',
                         payload => [
                             { ttl => 120,
                               body => [ 'aleax', 'archon', 'ki-rin' ] } ]);

=head1 DESCRIPTION

This library is a L<Net::HTTP::Spore>-based client for the message
queue component of OpenStack,
L<Zaqar|https://wiki.openstack.org/wiki/Marconi/specs/api/v1>
(previously known as "Marconi").

It is a straightforward client without bells and whistles.  The only
extra is the support of Rackspace authentication using their L<Cloud
Identity|http://docs.rackspace.com/queues/api/v1.0/cq-gettingstarted/content/Generating_Auth_Token.html>
token system.

=head1 ATTRIBUTES

=head2 base_url

(read-only string)

The base URL for all API queries, except for the Rackspace-specific
authentication.

=head2 client_uuid

(read-only string, defaults to a new UUID)

All API queries B<should> contain a "Client-ID" header (in practice,
some appear to work without this header).  If you do not provide a
value, a new one will be built with L<Data::UUID>.

The docs recommend reusing the same client UUID between restarts of
the client.

=head2 spore_client

(read-only object)

This is the L<Net::HTTP::Spore> client build with the
C<spore_description_file> attribute.  All API method calls will be
delegated to this object.

=head2 spore_description_file

(read-only required file path or URL)

Path to the SPORE specification file or remote resource.

A spec file for Zaqar v1.0 is provided in the distribution (see
F<share/marconi.spec.json>).

=head2 token

(read-only string with default predicate)

The token is automatically set when calling C<rackspace_authenticate>
successfully.  Once set, it will be sent in the "X-Auth-Token" header
with each query.

Rackspace invalidates the token after 24h, at which point all the
queries will start returning 403 Forbidden.  Consider using a module
such as L<Action::Retry> to re-authenticate.

=head1 METHODS

=head2 DELEGATED METHODS

All methods listed in L<the API
docs|https://wiki.openstack.org/wiki/Marconi/specs/api/v1> are
implemented by the SPORE client.  When a body is required, you must
provide it via the C<payload> parameter.

See also the F<share/marconi.spore.json> file for details.

All those methods can be called with an instance of
L<WebService::Zaqar> as invocant; they will be delegated to the SPORE
client.

=head2 rackspace_authenticate

  my $token = $client->rackspace_authenticate('https://identity.api.rackspacecloud.com/v2.0/tokens',
                                              $rackspace_account,
                                              $rackspace_key);

Sends an HTTP request to a L<Cloud
Identity|http://docs.rackspace.com/queues/api/v1.0/cq-gettingstarted/content/Generating_Auth_Token.html>
endpoint (or compatible) and sets the token received.

See also L</token>.

=head1 SEE ALSO

L<Net::HTTP::Spore>

=head1 AUTHOR

Fabrice Gabolde <fgabolde@weborama.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 Weborama

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301, USA.

=cut
