#!/usr/bin/perl

use strict;
use HTTP::Request::Common;
use HTTP::Cookies;
use LWP;
use Encode;

use RT::Test tests => 21;
my ($baseurl, $agent) = RT::Test->started_ok;
$agent->cookie_jar( HTTP::Cookies->new );

# get the top page
my $url = $agent->rt_base_url;
diag $url if $ENV{TEST_VERBOSE};
$agent->get($url);

is ($agent->{'status'}, 200, "Loaded a page");


# {{{ test a login

# follow the link marked "Login"

ok($agent->{form}->find_input('user'));

ok($agent->{form}->find_input('pass'));
ok ($agent->{'content'} =~ /username:/i);
$agent->field( 'user' => 'root' );
$agent->field( 'pass' => 'password' );
# the field isn't named, so we have to click link 0
$agent->click(0);
is($agent->{'status'}, 200, "Fetched the page ok");
ok( $agent->{'content'} =~ /Logout/i, "Found a logout link");



$agent->get($url."Ticket/Create.html?Queue=1");
is ($agent->{'status'}, 200, "Loaded Create.html");
$agent->form_number(3);
# Start with a string containing characters in latin1
my $string;
$string = Encode::decode_utf8("I18N Web Testing æøå");
$agent->field('Subject' => "Ticket with utf8 body");
$agent->field('Content' => $string);
ok($agent->submit(), "Created new ticket with $string as Content");
like( $agent->{'content'}, qr{$string} , "Found the content");
ok($agent->{redirected_uri}, "Did redirection");


$agent->get($url."Ticket/Create.html?Queue=1");
is ($agent->{'status'}, 200, "Loaded Create.html");
$agent->form_number(3);
# Start with a string containing characters in latin1
$string = Encode::decode_utf8("I18N Web Testing æøå");
$agent->field('Subject' => $string);
$agent->field('Content' => "Ticket with utf8 subject");
ok($agent->submit(), "Created new ticket with $string as Subject");

like( $agent->{'content'}, qr{$string} , "Found the content");

# Update time worked in hours
$agent->follow_link( text_regex => qr/Basics/ );
$agent->submit_form( form_number => 3,
    fields => { TimeWorked => 5, 'TimeWorked-TimeUnits' => "hours" }
);

like ($agent->{'content'}, qr/to &#39;300&#39;/, "5 hours is 300 minutes");

# }}}

# {{{ test an image

TODO: {
    todo_skip("Need to handle mason trying to compile images",1);
$agent->get( $url."NoAuth/images/test.png" );
my $file = RT::Test::get_relocatable_file(
  File::Spec->catfile(
    qw(.. .. share html NoAuth images test.png)
  )
);
is(
    length($agent->content),
    -s $file,
    "got a file of the correct size ($file)",
);
}
# }}}

# {{{ Query Builder tests
#
# XXX: hey-ho, we have these tests in t/web/query-builder
# TODO: move everything about QB there

my $response = $agent->get($url."Search/Build.html");
ok( $response->is_success, "Fetched " . $url."Search/Build.html" );

# Parsing TicketSQL
#
# Adding items

# set the first value
ok($agent->form_name('BuildQuery'));
$agent->field("AttachmentField", "Subject");
$agent->field("AttachmentOp", "LIKE");
$agent->field("ValueOfAttachment", "aaa");
$agent->submit("AddClause");

# set the next value
ok($agent->form_name('BuildQuery'));
$agent->field("AttachmentField", "Subject");
$agent->field("AttachmentOp", "LIKE");
$agent->field("ValueOfAttachment", "bbb");
$agent->submit("AddClause");

ok($agent->form_name('BuildQuery'));

# get the query
my $query = $agent->current_form->find_input("Query")->value;
# strip whitespace from ends
$query =~ s/^\s*//g;
$query =~ s/\s*$//g;

# collapse other whitespace
$query =~ s/\s+/ /g;

is ($query, "Subject LIKE 'aaa' AND Subject LIKE 'bbb'");

# - new items go one level down
# - add items at currently selected level
# - if nothing is selected, add at end, one level down
#
# move left
# - error if nothing selected
# - same item should be selected after move
# - can't move left if you're at the top level
#
# move right
# - error if nothing selected
# - same item should be selected after move
# - can always move right (no max depth...should there be?)
#
# move up
# - error if nothing selected
# - same item should be selected after move
# - can't move up if you're first in the list
#
# move down
# - error if nothing selected
# - same item should be selected after move
# - can't move down if you're last in the list
#
# toggle
# - error if nothing selected
# - change all aggregators in the grouping
# - don't change any others
#
# delete
# - error if nothing selected
# - delete currently selected item
# - delete all children of a grouping
# - if delete leaves a node with no children, delete that, too
# - what should be selected?
#
# Clear
# - clears entire query
# - clears it from the session, too

# }}}


1;
