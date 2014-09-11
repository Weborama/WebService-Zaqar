#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;
use Carp;
use autodie;
use utf8;

# for the DumpToScalar middleware
use lib 't/lib';

use Test::More;
use Test::SetupTeardown;

use WebService::Zaqar;
use JSON;

my $requests;
my $mock_server = {
    '/v1/queues' => sub {
        my $req = shift;
        $req->new_response(
            200, [],
            JSON::encode_json({
                links => [ { rel => 'next',
                             href => '/v1/queues?marker=kooleo&limit=15' }, ],
                queues => [ { name => 'boomerang',
                              href => '/v1/queues/boomerang',
                              metadata => {} },
                            { name => 'kooleo',
                              href => '/v1/queues/kooleo',
                              metadata => { something => 'something_else' } } ] }));
    },
    '/v1/madeup' => sub {
        my $req = shift;
        $req->new_response(204, [], JSON::encode_json({ foo => 'bar' }));
    },
};

my $environment = Test::SetupTeardown->new(setup => sub { @{$requests} = () });

$environment->run_test('follow links', sub {
    my $client = WebService::Zaqar->new(base_url => 'http://localhost',
                                        spore_description_file => 'share/marconi.spore.json',
                                        client_uuid => 'tomato',
                                        token => 'potato');
    $client->spore_client->enable('DumpToScalar',
                                  dump_log => $requests);
    $client->spore_client->enable('Mock',
                                  tests => $mock_server);
    my $response = $client->list_queues(limit => 10);
    shift @{$requests};
    my $followup = $response->parameters_for_following_link("next");
    is_deeply({ @{$followup} }, { limit => 15, marker => 'kooleo' },
              q{... and having a rel: "next" link allows us to generate a followup request});
    ok($client->list_queues(limit => 10, @{$followup}),
       q{... and that request is valid});
                       });

done_testing;
