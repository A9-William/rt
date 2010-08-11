#!/usr/bin/perl

use strict;
use warnings;

use RT::Test tests => 44;
RT->Config->Set( 'Timezone' => 'EST5EDT' ); # -04:00

my ($baseurl, $m) = RT::Test->started_ok;
ok $m->login, 'logged in as root';
my $root = RT::User->new( $RT::SystemUser );
ok( $root->Load('root'), 'load root user' );

my $cf_name = 'test cf datetime';

my $cfid;
diag "Create a CF" if $ENV{'TEST_VERBOSE'};
{
    $m->follow_link( text => 'Configuration' );
    $m->title_is(q/RT Administration/, 'admin screen');
    $m->follow_link( text => 'Custom Fields' );
    $m->title_is(q/Select a Custom Field/, 'admin-cf screen');
    $m->follow_link( text => 'Create' );
    $m->submit_form(
        form_name => "ModifyCustomField",
        fields => {
            Name          => $cf_name,
            TypeComposite => 'DateTime-1',
            LookupType    => 'RT::Queue-RT::Ticket',
        },
    );
    $m->content_like( qr/Object created/, 'created CF sucessfully' );
    $cfid = $m->form_name('ModifyCustomField')->value('id');
    ok $cfid, "found id of the CF in the form, it's #$cfid";
}

diag "apply the CF to General queue" if $ENV{'TEST_VERBOSE'};
my $queue = RT::Test->load_or_create_queue( Name => 'General' );
ok $queue && $queue->id, 'loaded or created queue';

{
    $m->follow_link( text => 'Queues' );
    $m->title_is(q/Admin queues/, 'admin-queues screen');
    $m->follow_link( text => 'General' );
    $m->title_is(q/Editing Configuration for queue General/, 'admin-queue: general');
    $m->follow_link( text => 'Ticket Custom Fields' );
    $m->title_is(q/Edit Custom Fields for General/, 'admin-queue: general cfid');

    $m->form_name('EditCustomFields');
    $m->tick( "AddCustomField" => $cfid );
    $m->click('UpdateCFs');

    $m->content_like( qr/Object created/, 'TCF added to the queue' );
}

diag 'check valid inputs with various timezones in ticket create page' if $ENV{'TEST_VERBOSE'};
{
    my ( $ticket, $id );

    $m->submit_form(
        form_name => "CreateTicketInQueue",
        fields => { Queue => 'General' },
    );
    $m->content_like(qr/Select datetime/, 'has cf field');

    $m->submit_form(
        form_name => "TicketCreate",
        fields    => {
            Subject                                       => 'test 2010-05-04 13:00:01',
            Content                                       => 'test',
            "Object-RT::Ticket--CustomField-$cfid-Values" => '2010-05-04 13:00:01',
        },
    );
    ok( ($id) = $m->content =~ /Ticket (\d+) created/,
        "created ticket $id" );

    $ticket = RT::Ticket->new( $RT::SystemUser );
    $ticket->Load($id);
    is(
        $ticket->CustomFieldValues($cfid)->First->Content,
        '2010-05-04 17:00:01',
        'date in db is in UTC'
    );

    $m->content_like(qr/test cf datetime:/, 'has no cf datetime field on the page');
    $m->content_like(qr/Tue May 04 13:00:01 2010/, 'has cf datetime value on the page');

    $root->SetTimezone( 'Asia/Shanghai' );
    # interesting that $m->reload doesn't work
    $m->get_ok( $m->uri );
    $m->content_like(qr/Wed May 05 01:00:01 2010/, 'cf datetime value respects user timezone');

    $m->submit_form(
        form_name => "CreateTicketInQueue",
        fields => { Queue => 'General' },
    );
    $m->submit_form(
        form_name => "TicketCreate",
        fields    => {
            Subject                                       => 'test 2010-05-06 07:00:01',
            Content                                       => 'test',
            "Object-RT::Ticket--CustomField-$cfid-Values" => '2010-05-06 07:00:01',
        },
    );
    ok( ($id) = $m->content =~ /Ticket (\d+) created/,
        "created ticket $id" );
    $ticket = RT::Ticket->new( $RT::SystemUser );
    $ticket->Load($id);
    is(
        $ticket->CustomFieldValues($cfid)->First->Content,
        '2010-05-05 23:00:01',
        'date in db is in UTC'
    );

    $m->content_like(qr/test cf datetime:/, 'has no cf datetime field on the page');
    $m->content_like(qr/Thu May 06 07:00:01 2010/, 'cf datetime input respects user timezone');
    $root->SetTimezone( 'EST5EDT' ); # back to -04:00
    $m->get_ok( $m->uri );
    $m->content_like(qr/Wed May 05 19:00:01 2010/, 'cf datetime value respects user timezone');
}


diag 'check search build page' if $ENV{'TEST_VERBOSE'};
{
    $m->get_ok( $baseurl . '/Search/Build.html?Query=Queue=1' );

    $m->form_number(3);
    my ($cf_op) =
      $m->find_all_inputs( type => 'option', name_regex => qr/test cf datetime/ );
    is_deeply(
        [ $cf_op->possible_values ],
        [ '<', '=', '>' ],
        'right oprators'
    );

    my ($cf_field) =
      $m->find_all_inputs( type => 'text', name_regex => qr/test cf datetime/ );
    $m->submit_form(
        fields => {
            $cf_op->name    => '=',
            $cf_field->name => '2010-05-04'
        },
        button => 'DoSearch',
    );

    $m->content_contains( 'Found 1 ticket', 'Found 1 ticket' );
    $m->content_contains( '2010-05-04',     'got the right ticket' );
    $m->content_lacks( '2010-05-06', 'did not get the wrong ticket' );

    my $shanghai = RT::Test->load_or_create_user(
        Name     => 'shanghai',
        Password => 'password',
        Timezone => 'Asia/Shanghai',
    );
    ok( $shanghai->PrincipalObj->GrantRight(
        Right  => 'SuperUser',
        Object => $RT::System,
    ));
    $m->login( 'shanghai', 'password' );

    $m->get_ok( $baseurl . '/Search/Build.html?Query=Queue=1' );
    $m->form_number(3);
    $m->submit_form(
        fields => {
            $cf_op->name    => '=',
            $cf_field->name => '2010-05-05'
        },
        button => 'DoSearch',
    );
    $m->content_contains( 'Found 1 ticket', 'Found 1 ticket' );

    $m->get_ok( $baseurl . '/Search/Build.html?Query=Queue=1' );
    $m->form_number(3);
    $m->submit_form(
        fields => {
            $cf_op->name    => '<',
            $cf_field->name => '2010-05-06'
        },
        button => 'DoSearch',
    );
    $m->content_contains( 'Found 2 ticket', 'Found 2 ticket' );

    $m->get_ok( $baseurl . '/Search/Build.html?Query=Queue=1' );
    $m->form_number(3);
    $m->submit_form(
        fields => {
            $cf_op->name    => '>',
            $cf_field->name => '2010-05-03',
        },
        button => 'DoSearch',
    );
    $m->content_contains( 'Found 2 tickets', 'Found 2 tickets' );

    $m->get_ok( $baseurl . '/Search/Build.html?Query=Queue=1' );
    $m->form_number(3);
    $m->submit_form(
        fields => {
            $cf_op->name    => '=',
            $cf_field->name => '2010-05-04 16:00:01',
        },
        button => 'DoSearch',
    );
    $m->content_contains( 'Found 1 ticket', 'Found 1 ticket' );

    $m->get_ok( $baseurl . '/Search/Build.html?Query=Queue=1' );
    $m->form_number(3);
    $m->submit_form(
        fields => {
            $cf_op->name    => '=',
            $cf_field->name => '2010-05-05 01:00:01',
        },
        button => 'DoSearch',
    );
    $m->content_contains( 'Found 1 ticket', 'Found 1 ticket' );
}

diag 'check invalid inputs' if $ENV{'TEST_VERBOSE'};

{
    $m->submit_form(
        form_name => "CreateTicketInQueue",
        fields => { Queue => 'General' },
    );
    my $form = $m->form_name("TicketCreate");

    $m->submit_form(
        form_name => "TicketCreate",
        fields    => {
            Subject                                       => 'test',
            Content                                       => 'test',
            "Object-RT::Ticket--CustomField-$cfid-Values" => 'foodate',
        },
    );
    $m->content_like(qr/Ticket \d+ created/, "a ticket is created succesfully");

    $m->content_like(qr/test cf datetime:/, 'has no cf datetime field on the page');
    $m->content_unlike(qr/foodate/, 'invalid dates not set');
}
