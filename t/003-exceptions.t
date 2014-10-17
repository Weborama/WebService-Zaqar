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
use Test::Exception;
use Test::SetupTeardown;

use WebService::Zaqar;

my $requests;
my $mock_server = {
    '/v1/queues/tomato' => sub {
        my $req = shift;
        $req->new_response(500, [], 'no response for tomatoes');
    },
    '/v1/queues/potato' => sub {
        my $req = shift;
        $req->new_response(500, [], { error => 'go away' });
    },
    '/v1/queues/chirimoya' => sub {
        my $req = shift;
        # fake an internal exception!
        $req->new_response(599, [], { error => 'internal stuff happened' });
    },
};

my $environment = Test::SetupTeardown->new(setup => sub { @{$requests} = () });

$environment->run_test('plain text 5xx response', sub {

    my $client = WebService::Zaqar->new(base_url => 'http://localhost',
                                        spore_description_file => 'share/marconi.spore.json',
                                        client_uuid => 'tomato');
    $client->spore_client->enable('DumpToScalar',
                                  dump_log => $requests);
    $client->spore_client->enable('Mock',
                                  tests => $mock_server);

    throws_ok(sub { $client->do_request(sub { $client->exists_queue(queue_name => 'tomato') }) },
              qr/HTTP 500: no response for tomatoes/,
              q{... and the exception is clearer than the default SPORE exception stringification});

                       });

$environment->run_test('JSON-encoded 5xx response', sub {

    my $client = WebService::Zaqar->new(base_url => 'http://localhost',
                                        spore_description_file => 'share/marconi.spore.json',
                                        client_uuid => 'tomato');
    $client->spore_client->enable('DumpToScalar',
                                  dump_log => $requests);
    $client->spore_client->enable('Mock',
                                  tests => $mock_server);

    throws_ok(sub { $client->do_request(sub { $client->exists_queue(queue_name => 'potato') }) },
              qr/HTTP 500: {"error":"go away"}/,
              q{... and the exception is clearer than the default SPORE exception stringification});

                       });

$environment->run_test('internal 599 response', sub {

    # 599s are usually thrown by LWP itself, when e.g. trying to hit
    # an https URI and SSL support is not available

    my $client = WebService::Zaqar->new(base_url => 'http://localhost',
                                        spore_description_file => 'share/marconi.spore.json',
                                        client_uuid => 'tomato');
    $client->spore_client->enable('DumpToScalar',
                                  dump_log => $requests);
    $client->spore_client->enable('Mock',
                                  tests => $mock_server);

    throws_ok(sub { $client->do_request(sub { $client->exists_queue(queue_name => 'chirimoya') }) },
              qr/internal stuff happened/,
              q{... and the exception is clearer than the default SPORE exception stringification});

                       });

done_testing;
