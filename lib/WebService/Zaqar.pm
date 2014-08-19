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
